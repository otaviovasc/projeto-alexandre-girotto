class PortalReservaController < ApplicationController
  layout "portal_reserva"
  skip_before_action :authenticate_user!
  before_action :require_fnrh_information_release!, only: [
    :inicio, :comprados, :atualizar_servico_comprado, :servicos, :adicionar,
    :remover, :revisar_servicos, :pagar, :confirmacao, :confirmacao_status
  ]
  before_action :ensure_service_purchase_window_open!, only: [:servicos, :adicionar, :remover, :revisar_servicos, :pagar]
  helper_method :food_service_for_observation?, :decoration_service_for_observation?,
                :fondue_service?, :photo_print_service?, :service_price_for,
                :portal_service_dates

  PARTNER_SERVICE_CREDIT_CARD_INTEREST_RATE = 3
  PHOTO_PRINT_ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png].freeze
  PHOTO_PRINT_MAX_FILE_SIZE = 10.megabytes
  PORTAL_CHECKIN_AFTERNOON_NOTE = "de tarde após check-in".freeze
  PORTAL_CHECKOUT_MORNING_NOTE = "de manhã antes do check-out".freeze

  # GET /minha-reserva
  def index
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
    @available_service_dates = available_service_dates(@reserva)
  end

  # PATCH /minha-reserva/comprados/:id
  def atualizar_servico_comprado
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path, alert: "Por favor, acesse sua reserva primeiro." and return
    end

    @reserva = Reserva.includes(:user, cabana: :filial).find(session[:portal_reserva_id])
    requested_ids = Array(params[:service_item_ids]).map(&:to_i).select(&:positive?)
    requested_ids = [params[:id].to_i] if requested_ids.blank?
    reserva_services = @reserva.reserva_services.includes(:service).where(id: requested_ids).to_a
    reserva_service = reserva_services.first

    if reserva_service.blank? || reserva_services.any? { |item| internal_service_for_portal?(item.service) }
      redirect_to portal_reserva_comprados_path, alert: "Serviço não encontrado." and return
    end

    blocked_service = reserva_services.detect { |item| !item.guest_change_allowed? }
    if blocked_service
      redirect_to portal_reserva_comprados_path, alert: blocked_service.guest_change_block_reason and return
    end

    new_date = parse_service_date(params[:service_date])
    unless new_date.present? && new_date.between?(@reserva.start_date, @reserva.end_date)
      redirect_to portal_reserva_comprados_path, alert: "Escolha uma data dentro do período da reserva." and return
    end

    ReservaService.transaction do
      reserva_services.each do |item|
        item.update!(
          service_date: new_date,
          observation: params[:observation].to_s.strip.presence
        )
      end
    end

    sync_all_reservas_to_sheets

    redirect_to portal_reserva_comprados_path, notice: "Serviço atualizado."
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
    @service_purchase_late_fee_amount = service_purchase_late_fee_amount_for(@reserva, @portal_cart_items)

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
    photo_uploads = photo_print_uploads

    if fondue_service?(service) && fondue_choice.blank?
      flash[:alert] = "Escolha se deseja fondue de queijo ou de chocolate."
      redirect_to portal_reserva_servicos_path and return
    end

    if (photo_print_error = photo_print_upload_error(service, photo_uploads))
      flash[:alert] = photo_print_error
      redirect_to portal_reserva_servicos_path and return
    end

    if service_dates_param.include?("all_days")
      dates_to_add = portal_service_dates(service, @reserva)
    else
      dates_to_add = service_dates_param.filter_map { |d| Date.parse(d) rescue nil }
    end

    if dates_to_add.empty?
      flash[:alert] = "Selecione pelo menos uma data válida."
      redirect_to portal_reserva_servicos_path and return
    end

    unless dates_to_add.all? { |date| portal_service_date_allowed?(service, @reserva, date) }
      flash[:alert] = portal_service_date_error_message(service)
      redirect_to portal_reserva_servicos_path and return
    end

    success = true
    created_cart_items = []

    begin
      CartItem.transaction do
        dates_to_add.each do |date|
          # Valida se a data está dentro do período da reserva
          if date >= @reserva.start_date && date <= @reserva.end_date
            cart_item = portal_cart_items(@reserva).new(
              cart:         portal_cart(@reserva),
              reserva:      @reserva,
              service:      service,
              quantity:     quantity,
              service_date: date,
              observation:   observation_for_service(service, date)
            )
            if cart_item.save
              created_cart_items << cart_item
            else
              success = false
            end
          end
        end

        attach_photo_print_files!(created_cart_items, photo_uploads) if success && photo_print_service?(service)
      end
    rescue PhotoPrintPdfGenerator::Error => e
      flash[:alert] = e.message
      redirect_to portal_reserva_servicos_path and return
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

  # GET /minha-reserva/revisar-servicos
  def revisar_servicos
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path, alert: "Sessão expirada." and return
    end

    @reserva = Reserva.includes(:user, cabana: :filial).find(session[:portal_reserva_id])
    expire_stale_portal_cart_items(@reserva)

    if (pending_payment = active_pending_portal_payment(@reserva))
      redirect_to portal_reserva_confirmacao_path(codigo: pending_payment.payment_order_code) and return
    end

    @portal_cart_items = portal_cart_items(@reserva).includes(:service).order(:service_date, :id)
    @service_purchase_late_fee_amount = service_purchase_late_fee_amount_for(@reserva, @portal_cart_items)

    if @portal_cart_items.empty?
      flash[:alert] = "Seu carrinho está vazio."
      redirect_to portal_reserva_servicos_path
    end
  end

  # POST /minha-reserva/pagar
  def pagar
    unless session[:portal_reserva_id].present?
      redirect_to portal_reserva_path and return
    end

    @reserva = Reserva.find(session[:portal_reserva_id])
    expire_stale_portal_cart_items(@reserva)
    @portal_cart_items = portal_cart_items(@reserva).includes(:service)
    @service_purchase_late_fee_amount = service_purchase_late_fee_amount_for(@reserva, @portal_cart_items)
    
    if @portal_cart_items.empty?
      flash[:alert] = "Seu carrinho está vazio."
      redirect_to portal_reserva_servicos_path and return
    end

    unless ActiveModel::Type::Boolean.new.cast(params[:service_terms_accepted])
      flash[:alert] = "Confirme as regras dos serviços adicionais para continuar."
      redirect_to portal_reserva_revisar_servicos_path and return
    end

    create_portal_payment_link

    redirect_to portal_reserva_confirmacao_path(codigo: @portal_payment_order_code), status: :see_other
  rescue PagarmePaymentLinkService::Error, CieloCheckoutService::Error => e
    Rails.logger.error("Portal payment error: #{e.message}")
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
    sync_cielo_checkout_status!(@purchased_services)
    @purchased_services = purchase_items_for_order(order_code)
    @payment_link_url = @purchased_services.first.payment_link_url
    @payment_status = purchase_payment_status(@purchased_services)
    @payment_status_label = payment_status_label(@payment_status)
    @payment_paid = @payment_status == "paid"
    @payment_open = @payment_status == "waiting_payment"
    @service_purchase_late_fee_amount = service_purchase_late_fee_amount_for(@reserva, @purchased_services)
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

    sync_cielo_checkout_status!(purchased_services)
    purchased_services = purchase_items_for_order(params[:codigo].to_s.strip)
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
    session.delete(:fnrh_portal_reserva_id)
    session.delete(:pending_terms_reserva_id)
    session.delete(:fnrh_terms_guest_name)
    redirect_to fnrh_terms_path, notice: "Você saiu do acesso da reserva."
  end

  private

  def food_service_for_observation?(service)
    normalized_name = service.name.to_s.parameterize

    ["almoco", "jantar", "piquenique", "cafe-da-manha", "fondue"].any? do |keyword|
      normalized_name.include?(keyword)
    end
  end

  def fondue_service?(service)
    service.name.to_s.parameterize.include?("fondue")
  end

  def photo_print_service?(service)
    service.respond_to?(:photo_print_service?) ? service.photo_print_service? : service.name.to_s.parameterize.match?(/foto.*impress/)
  end

  def decoration_service_for_observation?(service)
    normalized_name = service.name.to_s.parameterize

    ["decoracao", "petala", "luzinha", "espumante", "foto-impress"].any? do |keyword|
      normalized_name.include?(keyword)
    end
  end

  def observation_for_service(service, service_date = nil)
    notes = []
    notes << automatic_observation_for_service_date(service, service_date)

    notes << "Fondue: #{fondue_choice}" if fondue_service?(service)
    notes << params[:observation].to_s.strip if params[:observation].present?
    notes.compact_blank.join(". ").presence
  end

  def fondue_choice
    {
      "queijo" => "queijo",
      "chocolate" => "chocolate"
    }[params[:fondue_choice].to_s]
  end

  def service_price_for(service, reserva = @reserva)
    service.price_for(reserva)
  end

  def require_fnrh_information_release!
    return unless session[:portal_reserva_id].present?

    reserva = Reserva.find_by(id: session[:portal_reserva_id])
    return if reserva.blank? || reserva.fnrh_information_released?

    session[:fnrh_portal_reserva_id] = reserva.id

    respond_to do |format|
      format.html do
        redirect_to fnrh_terms_path, alert: "Conclua o pré-check-in para acessar os serviços e o material do hóspede."
      end
      format.json do
        render json: { found: false, paid: false, status: "fnrh_pending" }, status: :forbidden
      end
    end
  end

  def portal_service_dates(service, reserva = @reserva)
    return [] if reserva.blank? || reserva.start_date.blank? || reserva.end_date.blank?

    (reserva.start_date..reserva.end_date).select do |date|
      portal_service_date_allowed?(service, reserva, date)
    end
  end

  def portal_service_date_allowed?(service, reserva, date)
    return false if service.blank? || reserva.blank? || date.blank?
    return false if reserva.start_date.blank? || reserva.end_date.blank?
    return false unless date.between?(reserva.start_date, reserva.end_date)
    return false if checkout_date?(reserva, date) && checkout_blocked_service?(service)

    true
  end

  def checkout_blocked_service?(service)
    afternoon_checkin_note_service?(service) ||
      cold_cuts_service?(service) ||
      fondue_service?(service)
  end

  def automatic_observation_for_service_date(service, service_date)
    return if service_date.blank?

    return PORTAL_CHECKIN_AFTERNOON_NOTE if afternoon_checkin_note_service?(service)

    if massage_service?(service)
      return PORTAL_CHECKIN_AFTERNOON_NOTE if checkin_date?(@reserva, service_date)
      return PORTAL_CHECKOUT_MORNING_NOTE if checkout_date?(@reserva, service_date)
    end
  end

  def portal_service_date_error_message(service)
    if checkout_blocked_service?(service)
      "#{service.name} não pode ser selecionado para o dia do checkout."
    else
      "Selecione uma data válida para este serviço."
    end
  end

  def afternoon_checkin_note_service?(service)
    normalized_name = service.name.to_s.parameterize
    normalized_name.include?("trilha") ||
      normalized_name.include?("cavalo") ||
      normalized_name.include?("piquenique")
  end

  def massage_service?(service)
    service.name.to_s.parameterize.include?("massagem")
  end

  def cold_cuts_service?(service)
    service.name.to_s.parameterize.match?(/tabua.*frio/)
  end

  def checkin_date?(reserva, date)
    reserva.present? && date == reserva.start_date
  end

  def checkout_date?(reserva, date)
    reserva.present? && date == reserva.end_date
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
    order_code = portal_payment_order_code
    @portal_payment_order_code = order_code
    expires_in = 10
    late_fee_amount = service_purchase_late_fee_amount_for(@reserva, @portal_cart_items)

    payment_link = create_service_payment_link(
      order_code: order_code,
      items: payment_items,
      success_url: portal_reserva_confirmacao_url(codigo: order_code),
      failure_url: portal_reserva_servicos_url,
      expires_in: expires_in,
      max_installments: @reserva.service_max_installments
    )

    payment_expires_at = expires_in.minutes.from_now
    now = Time.current
    late_fee_assigned = false

    @portal_cart_items.find_each do |cart_item|
      unit_price = service_price_for(cart_item.service) || 0
      quantity = cart_item.quantity || 1
      cart_item_late_fee = late_fee_assigned ? 0.to_d : late_fee_amount
      late_fee_assigned = true

      cart_item.update_columns(
        payment_status: 'waiting_payment',
        payment_link_id: payment_link['id'],
        payment_link_url: payment_link['url'],
        payment_order_code: order_code,
        payment_expires_at: payment_expires_at,
        unit_price_paid: unit_price,
        total_paid: unit_price * quantity,
        purchased_after_service_deadline: @reserva.service_purchase_override_used?,
        service_late_fee_amount: cart_item_late_fee,
        updated_at: now
      )
    end

    payment_link
  end

  def create_service_payment_link(order_code:, items:, success_url:, failure_url:, expires_in:, max_installments:)
    if ServicePaymentProvider.cielo_checkout?
      CieloCheckoutService.new(
        merchant_id: @reserva.cabana.filial.cielo_checkout_merchant_id_for_payments,
        order_code: order_code,
        items: items,
        return_url: success_url,
        customer: payment_customer,
        soft_descriptor: "VILLAGGIO",
        max_installments: max_installments
      ).call
    else
      PagarmePaymentLinkService.new(
        api_key: @reserva.cabana.filial.pagarme_api_key_for_payments,
        name: "Serviços Reserva #{@reserva.id}",
        order_code: order_code,
        items: items,
        success_url: success_url,
        failure_url: failure_url,
        expires_in: expires_in,
        max_installments: max_installments,
        credit_card_interest_rate: service_credit_card_interest_rate
      ).call
    end
  end

  def portal_payment_order_code
    if ServicePaymentProvider.cielo_checkout?
      "PS#{@reserva.id.to_s.last(6)}#{Time.current.to_i}"
    else
      "portal-services-#{@reserva.id}-#{Time.current.to_i}"
    end
  end

  def payment_customer
    {
      name: @reserva.user&.name,
      email: @reserva.user&.email,
      phone: @reserva.guest_phone.presence || @reserva.user&.telephone
    }
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

  def sync_cielo_checkout_status!(purchased_services)
    purchased_services = Array(purchased_services).compact
    return unless ServicePaymentProvider.cielo_checkout?
    return if purchased_services.empty? || purchase_payment_status(purchased_services) == "paid"

    first_purchase = purchased_services.first
    order_code = first_purchase.payment_order_code.to_s
    return if order_code.blank?

    transaction, _lookup_source = CieloCheckoutService::TransactionQuery.new(
      client_id: first_purchase.reserva.cabana.filial.cielo_checkout_client_id_for_payments,
      client_secret: first_purchase.reserva.cabana.filial.cielo_checkout_client_secret_for_payments
    ).find_by_best_identifier(
      order_number: order_code,
      checkout_order_number: first_purchase.payment_link_id
    )

    status = CieloCheckoutService.payment_status_from_transaction(transaction)
    return if status.blank?

    query_id = transaction["checkoutOrderNumber"].presence ||
               transaction["checkout_order_number"].presence ||
               first_purchase.payment_link_id
    remember_cielo_checkout_order_number(first_purchase.payment_order_code, query_id)

    PaymentStatusProcessor.call(
      identifiers: [first_purchase.payment_order_code, first_purchase.payment_link_id, query_id],
      status: status
    )
  rescue CieloCheckoutService::Error => e
    Rails.logger.warn("Unable to sync Cielo Checkout status from portal: #{e.message}")
  end

  def remember_cielo_checkout_order_number(order_code, checkout_order_number)
    return if order_code.blank? || checkout_order_number.blank?

    now = Time.current
    CartItem.where(payment_order_code: order_code).update_all(payment_link_id: checkout_order_number, updated_at: now)
    ReservaService.where(payment_order_code: order_code).update_all(payment_link_id: checkout_order_number, updated_at: now)
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

  def available_service_dates(reserva)
    return [] if reserva.start_date.blank? || reserva.end_date.blank?

    (reserva.start_date..reserva.end_date).to_a
  end

  def parse_service_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def sync_all_reservas_to_sheets
    return unless GoogleSheetsExportService.configured?

    GoogleSheetsExportService.export_reservas(
      Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
    )
  rescue => e
    Rails.logger.error("Erro ao sincronizar Sheets apos alteracao de servico pelo hospede: #{e.message}")
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
    services_total = grouped_services.sum do |_key, items|
      first_item = items.first
      quantity = items.sum { |item| item.quantity.to_i }
      unit_price = first_item.unit_price_paid || service_price_for(first_item.service, reserva) || 0

      unit_price * quantity
    end
    late_fee_amount = service_purchase_late_fee_amount_for(reserva, purchased_services)
    total = services_total + late_fee_amount

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

    if late_fee_amount.positive?
      lines << "- #{reserva.service_purchase_late_fee_label}: R$ #{format('%.2f', late_fee_amount).tr('.', ',')}"
    end

    lines << ""
    lines << "Total pago: R$ #{format('%.2f', total).tr('.', ',')}"

    lines.join("\n")
  end

  def payment_items
    service_items = @portal_cart_items.map do |reserva_service|
      service_date = reserva_service.service_date&.strftime('%d/%m')
      name = [reserva_service.service.name, service_date].compact.join(' - ')

      {
        id: reserva_service.id,
        name: name,
        unit_price: service_price_for(reserva_service.service),
        quantity: reserva_service.quantity
      }
    end
    late_fee_amount = service_purchase_late_fee_amount_for(@reserva, @portal_cart_items)
    fee_item = if late_fee_amount.positive?
                 {
                   id: "taxa-fora-prazo",
                   name: @reserva.service_purchase_late_fee_label,
                   unit_price: late_fee_amount,
                   quantity: 1
                 }
               end
    items = service_items + Array(fee_item)

    return items if items.size <= 10

    [{
      id: "reserva-#{@reserva.id}-servicos",
      name: "Serviços adicionais - Reserva #{@reserva.id}",
      unit_price: @portal_cart_items.sum { |reserva_service| service_price_for(reserva_service.service) * reserva_service.quantity } + late_fee_amount,
      quantity: 1
    }]
  end

  def service_purchase_late_fee_amount_for(reserva, items)
    items = Array(items)
    persisted_late_fee = items.sum do |item|
      next 0.to_d unless item.respond_to?(:service_late_fee_amount)

      (item.service_late_fee_amount || 0).to_d
    end

    return persisted_late_fee if persisted_late_fee.positive?
    return 0.to_d if items.empty?
    return 0.to_d if items.any? { |item| item.respond_to?(:payment_order_code) && item.payment_order_code.present? }

    reserva&.service_purchase_late_fee_amount || 0.to_d
  end

  def photo_print_uploads
    Array(params[:photo_print_images]).reject(&:blank?)
  end

  def photo_print_upload_error(service, uploads)
    return unless photo_print_service?(service)
    return "Envie as fotos para comprar Fotos Impressas." if uploads.empty?
    return "Envie no máximo 3 fotos." if uploads.size > 3

    invalid_type = uploads.any? { |upload| !PHOTO_PRINT_ALLOWED_CONTENT_TYPES.include?(upload.content_type.to_s) }
    return "Envie fotos em JPG ou PNG." if invalid_type

    oversized = uploads.any? { |upload| upload.respond_to?(:size) && upload.size.to_i > PHOTO_PRINT_MAX_FILE_SIZE }
    return "Cada foto pode ter no máximo 10 MB." if oversized
  end

  def attach_photo_print_files!(cart_items, uploads)
    raise PhotoPrintPdfGenerator::Error, "Envie as fotos para comprar Fotos Impressas." if cart_items.blank?

    primary_item = cart_items.first
    primary_item.photo_print_images.attach(uploads)
    PhotoPrintPdfGenerator.new(primary_item).call

    image_blobs = primary_item.photo_print_images.attachments.map(&:blob)
    pdf_blob = primary_item.photo_print_pdf.blob

    cart_items.drop(1).each do |cart_item|
      cart_item.photo_print_images.attach(image_blobs)
      cart_item.photo_print_pdf.attach(pdf_blob)
    end
  end

  def service_credit_card_interest_rate
    @reserva.partnership_reservation? ? PARTNER_SERVICE_CREDIT_CARD_INTEREST_RATE : 0
  end
end
