class PortalReservaController < ApplicationController
  layout "portal_reserva"
  skip_before_action :authenticate_user!
  before_action :ensure_service_purchase_window_open!, only: [:servicos, :adicionar, :remover, :pagar]

  # GET /minha-reserva
  def index
    # Se já tem reserva na sessão, redireciona direto pro catálogo
    if session[:portal_reserva_id].present?
      redirect_to portal_reserva_servicos_path
    end
  end

  # POST /minha-reserva/acessar
  def acessar
    reserva_id = params[:reserva_id].to_i
    identificador = params[:identificador].to_s.strip.downcase

    reserva = Reserva.find_by(id: reserva_id)

    if reserva.nil?
      flash[:alert] = "Reserva não encontrada. Verifique o código informado."
      redirect_to portal_reserva_path and return
    end

    user = reserva.user

    # Aceita email OU primeiro nome OU nome completo (case insensitive)
    nome_completo_match = user.name.to_s.downcase == identificador
    primeiro_nome_match = user.name.to_s.split.first.to_s.downcase == identificador
    email_match         = user.email.to_s.downcase == identificador

    unless nome_completo_match || primeiro_nome_match || email_match
      flash[:alert] = "Nome ou e-mail não corresponde a esta reserva."
      redirect_to portal_reserva_path and return
    end

    unless service_purchase_window_open?(reserva)
      reserva.reserva_services.where(status: "pending_portal").destroy_all
      flash[:alert] = service_purchase_closed_message(reserva)
      redirect_to portal_reserva_path and return
    end

    # Autenticação bem-sucedida: salva na sessão
    session[:portal_reserva_id] = reserva.id
    
    # Sempre começa com o carrinho vazio ao fazer login (limpa itens não pagos do portal)
    reserva.reserva_services.where(status: "pending_portal").destroy_all
    
    redirect_to portal_reserva_servicos_path
  end

  # GET /minha-reserva/servicos
  def servicos
    unless session[:portal_reserva_id].present?
      flash[:alert] = "Por favor, acesse sua reserva primeiro."
      redirect_to portal_reserva_path and return
    end

    @reserva = Reserva.includes(:user, cabana: :filial).find(session[:portal_reserva_id])
    @services = @reserva.cabana.filial.services.where(show_in_marketplace: true).order(:name)
    
    # Apenas itens adicionados nesta sessão do portal
    @portal_cart_items = @reserva.reserva_services.where(status: "pending_portal").includes(:service)

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
        rs = ReservaService.new(
          reserva:      @reserva,
          service:      service,
          quantity:     quantity,
          service_date: date,
          status:       "pending_portal"
        )
        success = false unless rs.save
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
    rs = @reserva.reserva_services.find_by(id: params[:id])

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
    @portal_cart_items = @reserva.reserva_services.includes(:service).where(status: "pending_portal")
    
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

    @purchased_services = ReservaService.includes(:service, reserva: [:user, :cabana])
                                        .where(payment_order_code: order_code)
                                        .where(reserva_id: session[:portal_reserva_id])
                                        .order(:service_date, :id)

    if @purchased_services.empty?
      flash[:alert] = "Nao encontramos o resumo desta compra."
      redirect_to portal_reserva_servicos_path and return
    end

    @reserva = @purchased_services.first.reserva
    @payment_link_url = @purchased_services.first.payment_link_url
    @payment_status = purchase_payment_status(@purchased_services)
    @payment_status_label = payment_status_label(@payment_status)
    @payment_paid = @payment_status == "paid"
    @summary_text = purchase_summary_text(@reserva, @purchased_services)
  end

  # GET /minha-reserva/confirmacao/status
  def confirmacao_status
    unless session[:portal_reserva_id].present?
      render json: { found: false, paid: false, status: nil }, status: :unauthorized and return
    end

    purchased_services = ReservaService
                         .where(payment_order_code: params[:codigo].to_s.strip)
                         .where(reserva_id: session[:portal_reserva_id])

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

  def ensure_service_purchase_window_open!
    return unless session[:portal_reserva_id].present?

    reserva = Reserva.find_by(id: session[:portal_reserva_id])
    return if reserva.blank? || service_purchase_window_open?(reserva)

    reserva.reserva_services.where(status: "pending_portal").destroy_all
    session.delete(:portal_reserva_id)
    flash[:alert] = service_purchase_closed_message(reserva)
    redirect_to portal_reserva_path
  end

  def service_purchase_window_open?(reserva)
    reserva.start_date.present? && Date.current <= service_purchase_cutoff_date(reserva)
  end

  def service_purchase_cutoff_date(reserva)
    reserva.start_date - 5
  end

  def service_purchase_closed_message(reserva)
    cutoff_date = service_purchase_cutoff_date(reserva).strftime("%d/%m/%Y")
    start_date = reserva.start_date.strftime("%d/%m/%Y")

    "As compras de servicos para esta reserva ficaram disponiveis ate #{cutoff_date}, 5 dias antes do check-in em #{start_date}."
  end

  def create_portal_payment_link
    order_code = "portal-services-#{@reserva.id}-#{Time.current.to_i}"
    @portal_payment_order_code = order_code
    expires_in = 30

    payment_link = PagarmePaymentLinkService.new(
      api_key: @reserva.cabana.filial.pagarme_api_key_for_payments,
      name: "Serviços Reserva #{@reserva.id}",
      order_code: order_code,
      items: pagarme_items,
      success_url: portal_reserva_confirmacao_url(codigo: order_code),
      failure_url: portal_reserva_servicos_url,
      expires_in: expires_in
    ).call

    payment_expires_at = expires_in.minutes.from_now
    now = Time.current

    @portal_cart_items.find_each do |reserva_service|
      unit_price = reserva_service.service.price || 0
      quantity = reserva_service.quantity || 1

      reserva_service.update_columns(
        status: 'pending_payment',
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
    grouped_services = purchased_services.group_by { |reserva_service| [reserva_service.service_id, reserva_service.service_date] }
    total = grouped_services.sum do |_key, items|
      first_item = items.first
      quantity = items.sum { |item| item.quantity.to_i }
      unit_price = first_item.unit_price_paid || first_item.service.price || 0

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
      unit_price = first_item.unit_price_paid || first_item.service.price || 0
      subtotal = unit_price * quantity
      service_date = first_item.service_date&.strftime("%d/%m/%Y")

      lines << "- #{first_item.service.name} | #{quantity} #{quantity == 1 ? 'unidade' : 'unidades'} | #{service_date} | R$ #{format('%.2f', subtotal).tr('.', ',')}"
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
        unit_price: reserva_service.service.price,
        quantity: reserva_service.quantity
      }
    end

    return items if items.size <= 10

    [{
      id: "reserva-#{@reserva.id}-servicos",
      name: "Serviços adicionais - Reserva #{@reserva.id}",
      unit_price: @portal_cart_items.sum { |reserva_service| reserva_service.service.price * reserva_service.quantity },
      quantity: 1
    }]
  end
end
