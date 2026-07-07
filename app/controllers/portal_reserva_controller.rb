class PortalReservaController < ApplicationController
  layout "portal_reserva"
  skip_before_action :authenticate_user!
  before_action :ensure_service_purchase_window_open!, only: [:servicos, :adicionar, :remover, :pagar]
  helper_method :food_service_for_observation?, :decoration_service_for_observation?, :service_price_for

  # GET /minha-reserva
  def index
    # Se já tem reserva na sessão, redireciona para as opções do portal
    if session[:portal_reserva_id].present?
      redirect_to portal_reserva_inicio_path
    end
  end

  # POST /minha-reserva/acessar
  def acessar
    reserva_id = params[:reserva_id].to_i
    identificador = params[:identificador].to_s

    reserva = Reserva.find_by(id: reserva_id)

    if reserva.nil?
      flash[:alert] = "Reserva não encontrada. Verifique o código informado."
      redirect_to portal_reserva_path and return
    end

    unless reserva.matches_reservation_identifier?(identificador)
      flash[:alert] = "Nome ou e-mail não corresponde a esta reserva."
      redirect_to portal_reserva_path and return
    end

    # Autenticação bem-sucedida: salva na sessão
    session[:portal_reserva_id] = reserva.id
    
    expire_stale_portal_cart_items(reserva)
    
    redirect_to portal_reserva_inicio_path
  end

  # GET /minha-reserva/inicio
  def inicio
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path, alert: "Por favor, acesse sua reserva primeiro." and return
    end

    @reserva = Reserva.includes(:user, cabana: :filial).find(session[:portal_reserva_id])
    expire_stale_portal_cart_items(@reserva)
    @purchased_services_count = reservation_services_for_portal(@reserva).count + operational_services_for_portal(@reserva).count
  end

  # GET /minha-reserva/comprados
  def comprados
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path, alert: "Por favor, acesse sua reserva primeiro." and return
    end

    @reserva = Reserva.includes(:user, cabana: :filial).find(session[:portal_reserva_id])
    @purchased_services = reservation_services_for_portal(@reserva)
    @operational_services = operational_services_for_portal(@reserva)
  end

  # GET /minha-reserva/servicos
  def servicos
    unless session[:portal_reserva_id].present?
      flash[:alert] = "Por favor, acesse sua reserva primeiro."
      redirect_to portal_reserva_path and return
    end

    @reserva = Reserva.includes(:user, cabana: :filial).find(session[:portal_reserva_id])
    @services = @reserva.cabana.filial.services
                       .where(show_in_marketplace: [true, nil])
                       .order(:name)

    expire_stale_portal_cart_items(@reserva)

    if (pending_payment = active_pending_portal_payment(@reserva))
      redirect_to portal_reserva_confirmacao_path(codigo: pending_payment.payment_order_code) and return
    end
    
    # Apenas itens adicionados nesta sessão do portal
    @portal_cart_items = portal_cart_items(@reserva).includes(:service)

    # Datas disponíveis para selecionar (dentro do período da reserva)
    @available_dates = (@reserva.start_date..@reserva.end_date).to_a
  end

  # POST /minha-reserva/adicionar
  def adicionar
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path, alert: "Sessão expirada." and return
    end

    @reserva = Reserva.includes(cabana: :filial).find(session[:portal_reserva_id])
    service  = @reserva.cabana.filial.services.find(params[:service_id])
    quantity = 1
    service_dates_param = params[:service_dates] || []
    observation = observation_for_service(service)

    if service_dates_param.include?("all_days")
      dates_to_add = (@reserva.start_date..@reserva.end_date).to_a
    else
      dates_to_add = service_dates_param.filter_map { |d| Date.parse(d) rescue nil }
    end

    if dates_to_add.empty?
      flash[:alert] = "Selecione pelo menos uma data válida."
      redirect_to portal_reserva_servicos_path and return
    end

    success = true
    dates_to_add.each do |date|
      # Valida se a data está dentro do período da reserva
      if date >= @reserva.start_date && date <= @reserva.end_date
        cart_item = portal_cart_items(@reserva).new(
          cart:         portal_cart(@reserva),
          reserva:      @reserva,
          service:      service,
          quantity:     quantity,
          service_date: date,
          observation:   observation
        )
        success = false unless cart_item.save
      end
    end

    if success
      flash[:notice] = "\"#{service.name}\" adicionado com sucesso!"
    else
      flash[:alert] = "Houve um erro ao adicionar alguns dias deste serviço."
    end

    redirect_to portal_reserva_servicos_path
  end

  # DELETE /minha-reserva/remover/:id
  def remover
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path and return
    end

    @reserva = Reserva.find(session[:portal_reserva_id])
    rs = portal_cart_items(@reserva).find_by(id: params[:id])

    if rs
      rs.destroy
      flash[:notice] = "Serviço removido."
    else
      flash[:alert] = "Serviço não encontrado."
    end

    redirect_to portal_reserva_servicos_path
  end

  # POST /minha-reserva/pagar
  def pagar
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path and return
    end

    @reserva = Reserva.find(session[:portal_reserva_id])
    expire_stale_portal_cart_items(@reserva)
    @portal_cart_items = portal_cart_items(@reserva).includes(:service)
    
    if @portal_cart_items.empty?
      flash[:alert] = "Seu carrinho está vazio."
      redirect_to portal_reserva_servicos_path and return
    end

    payment_link = create_portal_payment_link

    redirect_to portal_reserva_confirmacao_path(codigo: @portal_payment_order_code), status: :see_other
  rescue PagarmePaymentLinkService::Error => e
    Rails.logger.error("Pagar.me portal payment error: #{e.message}")
    flash[:alert] = e.message
    redirect_to portal_reserva_servicos_path
  rescue => e
    Rails.logger.error("Unexpected portal payment error: #{e.message}")
    flash[:alert] = "Nao foi possivel iniciar o pagamento. Tente novamente."
    redirect_to portal_reserva_servicos_path
  end

  # GET /minha-reserva/confirmacao
  def confirmacao
    unless session[:portal_reserva_id].present?
      flash[:alert] = "Sessao expirada. Acesse sua reserva novamente."
      redirect_to portal_reserva_path and return
    end

    order_code = params[:codigo].to_s.strip
    expire_stale_portal_cart_items(Reserva.find(session[:portal_reserva_id]))

    @purchased_services = purchase_items_for_order(order_code)

    if @purchased_services.empty?
      flash[:alert] = "Nao encontramos o resumo desta compra."
      redirect_to portal_reserva_servicos_path and return
    end

    @reserva = @purchased_services.first.reserva
    @payment_link_url = @purchased_services.first.payment_link_url
    @payment_status = purchase_payment_status(@purchased_services)
    @payment_status_label = payment_status_label(@payment_status)
    @payment_paid = @payment_status == "paid"
    @payment_open = @payment_status == "waiting_payment"
    @summary_text = purchase_summary_text(@reserva, @purchased_services)
  end

  # GET /minha-reserva/confirmacao/status
  def confirmacao_status
    unless session[:portal_reserva_id].present?
      render json: { found: false, paid: false, status: nil }, status: :unauthorized and return
    end

    expire_stale_portal_cart_items(Reserva.find(session[:portal_reserva_id]))
    purchased_services = purchase_items_for_order(params[:codigo].to_s.strip)

    if purchased_services.empty?
      render json: { found: false, paid: false, status: nil }, status: :not_found and return
    end

    status = purchase_payment_status(purchased_services)

    render json: {
      found: true,
      paid: status == "paid",
      status: status,
      status_label: payment_status_label(status)
    }
  end

  # DELETE /minha-reserva/sair
  def sair
    session.delete(:portal_reserva_id)
    redirect_to portal_reserva_path, notice: "Você saiu do portal da reserva."
  end

  private

  def food_service_for_observation?(service)
    normalized_name = service.name.to_s.parameterize

    ["almoco", "jantar", "piquenique", "cafe-da-manha"].any? do |keyword|
      normalized_name.include?(keyword)
    end
  end

  def decoration_service_for_observation?(service)
    normalized_name = service.name.to_s.parameterize

    ["decoracao", "petala", "luzinha", "espumante", "foto-impress"].any? do |keyword|
      normalized_name.include?(keyword)
    end
  end

  def observation_for_service(service)
    return unless food_service_for_observation?(service) || decoration_service_for_observation?(service)

    params[:observation].to_s.strip.presence
  end

  def service_price_for(service, reserva = @reserva)
    service.price_for(reserva)
  end

  def ensure_service_purchase_window_open!
    return unless session[:portal_reserva_id].present?

    reserva = Reserva.find_by(id: session[:portal_reserva_id])
    return if reserva.blank? || reserva.service_purchase_window_open?

    portal_cart_items(reserva).destroy_all
    flash[:alert] = reserva.service_purchase_closed_message
    redirect_to portal_reserva_inicio_path
  end

  def create_portal_payment_link
    order_code = "portal-services-#{@reserva.id}-#{Time.current.to_i}"
    @portal_payment_order_code = order_code
    expires_in = 10

    payment_link = PagarmePaymentLinkService.new(
      api_key: @reserva.cabana.filial.pagarme_api_key_for_payments,
      name: "Serviços Reserva #{@reserva.id}",
      order_code: order_code,
      items: pagarme_items,
      success_url: portal_reserva_confirmacao_url(codigo: order_code),
      failure_url: portal_reserva_servicos_url,
      expires_in: expires_in,
      max_installments: @reserva.service_max_installments
    ).call

    payment_expires_at = expires_in.minutes.from_now
    now = Time.current

    @portal_cart_items.find_each do |cart_item|
      unit_price = service_price_for(cart_item.service) || 0
      quantity = cart_item.quantity || 1

      cart_item.update_columns(
        payment_status: 'waiting_payment',
        payment_link_id: payment_link['id'],
        payment_link_url: payment_link['url'],
        payment_order_code: order_code,
        payment_expires_at: payment_expires_at,
        unit_price_paid: unit_price,
        total_paid: unit_price * quantity,
        updated_at: now
      )
    end

    payment_link
  end

  def portal_cart(reserva)
    reserva.user.cart || reserva.user.create_cart
  end

  def portal_cart_items(reserva)
    portal_cart(reserva)
      .cart_items
      .where(reserva: reserva, item_id: nil, payment_status: [nil, 'refused'])
  end

  def active_pending_portal_payment(reserva)
    portal_cart(reserva)
      .cart_items
      .where(reserva: reserva, item_id: nil, payment_status: 'waiting_payment')
      .where('payment_expires_at IS NULL OR payment_expires_at > ?', Time.current)
      .where.not(payment_order_code: nil)
      .first
  end

  def expire_stale_portal_cart_items(reserva)
    portal_cart(reserva)
      .cart_items
      .where(reserva: reserva, item_id: nil, payment_status: 'waiting_payment')
      .where('payment_expires_at <= ?', Time.current)
      .update_all(payment_status: 'canceled', updated_at: Time.current)
  end

  def purchase_items_for_order(order_code)
    cart_items = CartItem.includes(:service, reserva: [:user, :cabana])
                         .where(payment_order_code: order_code, reserva_id: session[:portal_reserva_id])
                         .order(:service_date, :id)

    return cart_items if cart_items.any?

    ReservaService.includes(:service, reserva: [:user, :cabana])
                  .where(payment_order_code: order_code, reserva_id: session[:portal_reserva_id])
                  .order(:service_date, :id)
  end

  def reservation_services_for_portal(reserva)
    reserva.reserva_services
           .includes(:service)
           .order(:service_date, :id)
           .reject { |reserva_service| internal_service_for_portal?(reserva_service.service) }
  end

  def internal_service_for_portal?(service)
    return true if CleaningServicesAssigner.cleaning_service?(service)

    normalized_name = service.name.to_s.parameterize
    evaluation_service = normalized_name.include?("enviar") && normalized_name.include?("avaliacao")
    charge_service = normalized_name.split("-").include?("cobrar")

    evaluation_service || charge_service
  end

  def operational_services_for_portal(reserva)
    services = []
    services << { name: "Early check-in", date: reserva.start_date } if reserva.early_checkin?
    services << { name: "Late checkout", date: reserva.end_date } if reserva.late_checkout?
    services
  end

  def purchase_payment_status(purchased_services)
    statuses = purchased_services.map { |reserva_service| reserva_service.payment_status.to_s }.uniq
    return "paid" if statuses == ["paid"]
    return "refused" if statuses.include?("refused")
    return "canceled" if statuses.include?("canceled")

    "waiting_payment"
  end

  def payment_status_label(status)
    {
      "paid" => "Pago",
      "waiting_payment" => "Aguardando pagamento",
      "refused" => "Pagamento recusado",
      "canceled" => "Pagamento cancelado"
    }.fetch(status.to_s, "Aguardando pagamento")
  end

  def purchase_summary_text(reserva, purchased_services)
    grouped_services = purchased_services.group_by do |reserva_service|
      [reserva_service.service_id, reserva_service.service_date, reserva_service.observation.to_s.strip]
    end
    total = grouped_services.sum do |_key, items|
      first_item = items.first
      quantity = items.sum { |item| item.quantity.to_i }
      unit_price = first_item.unit_price_paid || service_price_for(first_item.service, reserva) || 0

      unit_price * quantity
    end

    lines = [
      "Resumo da compra - Villaggio Girotto",
      "Cliente: #{reserva.user.name}",
      "Reserva: ##{reserva.id}",
      "Cabana: #{reserva.cabana.name}",
      "",
      "Servicos comprados:"
    ]

    grouped_services.each_value do |items|
      first_item = items.first
      quantity = items.sum { |item| item.quantity.to_i }
      unit_price = first_item.unit_price_paid || service_price_for(first_item.service, reserva) || 0
      subtotal = unit_price * quantity
      service_date = first_item.service_date&.strftime("%d/%m/%Y")
      observation = first_item.observation.to_s.strip

      line = "- #{first_item.service.name} | #{quantity} #{quantity == 1 ? 'unidade' : 'unidades'} | #{service_date} | R$ #{format('%.2f', subtotal).tr('.', ',')}"
      line += " | Obs: #{observation}" if observation.present?
      lines << line
    end

    lines << ""
    lines << "Total pago: R$ #{format('%.2f', total).tr('.', ',')}"

    lines.join("\n")
  end

  def pagarme_items
    items = @portal_cart_items.map do |reserva_service|
      service_date = reserva_service.service_date&.strftime('%d/%m')
      name = [reserva_service.service.name, service_date].compact.join(' - ')

      {
        id: reserva_service.id,
        name: name,
        unit_price: service_price_for(reserva_service.service),
        quantity: reserva_service.quantity
      }
    end

    return items if items.size <= 10

    [{
      id: "reserva-#{@reserva.id}-servicos",
      name: "Serviços adicionais - Reserva #{@reserva.id}",
      unit_price: @portal_cart_items.sum { |reserva_service| service_price_for(reserva_service.service) * reserva_service.quantity },
      quantity: 1
    }]
  end
end
