class ReservaPaymentsController < ApplicationController
  layout 'portal_reserva'

  skip_before_action :authenticate_user!
  before_action :set_reserva_payment

  def show
    refresh_payment_status!
    assign_payment_page_details
  end

  def accept_terms
    refresh_payment_status!
    assign_payment_page_details

    if payment_link_unavailable?
      flash.now[:alert] = 'Este link não está mais disponível para pagamento.'
      render :show, status: :unprocessable_entity
      return
    end

    unless ActiveModel::Type::Boolean.new.cast(params[:terms_accepted])
      flash.now[:alert] = 'Confirme o aceite dos termos para continuar.'
      render :show, status: :unprocessable_entity
      return
    end

    name = params[:terms_acceptance_name].to_s.squish
    if name.split(/\s+/).size < 2
      flash.now[:alert] = 'Informe nome e sobrenome do responsável pela reserva.'
      render :show, status: :unprocessable_entity
      return
    end

    @reserva_payment.update!(
      terms_accepted_at: Time.current,
      terms_acceptance_name: name,
      terms_acceptance_ip: request.remote_ip,
      terms_acceptance_user_agent: request.user_agent
    )

    redirect_to reserva_payment_path(token: @reserva_payment.terms_token), notice: 'Termos aceitos. Você já pode seguir para o pagamento.'
  end

  private

  def set_reserva_payment
    @reserva_payment = ReservaPayment.includes(reserva: [:user, :reserva_payments, { cabana: :filial }]).find_by!(terms_token: params[:token])
  end

  def refresh_payment_status!
    @reserva = @reserva_payment.reserva
    sync_cielo_checkout_status!
    @reserva_payment.reload
    @reserva = @reserva_payment.reserva
    expire_payment_if_needed!
    @reserva_payment.reload
    @reserva = @reserva_payment.reserva
  end

  def sync_cielo_checkout_status!
    return unless @reserva_payment.waiting_payment?
    return if @reserva_payment.payment_order_code.blank?

    filial = @reserva_payment.reserva.cabana.filial
    transaction = CieloCheckoutService::TransactionQuery.new(
      client_id: filial.cielo_checkout_client_id_for_payments,
      client_secret: filial.cielo_checkout_client_secret_for_payments
    ).find_by_order_number(@reserva_payment.payment_order_code)

    status = CieloCheckoutService.payment_status_from_transaction(transaction)
    return if status.blank?

    checkout_order_number = transaction['checkoutOrderNumber'].presence || @reserva_payment.payment_link_id
    remember_cielo_checkout_order_number(checkout_order_number)

    PaymentStatusProcessor.call(
      identifiers: [@reserva_payment.payment_order_code, @reserva_payment.payment_link_id, checkout_order_number],
      status: status
    )
  rescue CieloCheckoutService::Error => e
    Rails.logger.warn("Unable to sync Cielo Checkout reservation payment status: #{e.message}")
  end

  def remember_cielo_checkout_order_number(checkout_order_number)
    return if checkout_order_number.blank?
    return if @reserva_payment.payment_link_id == checkout_order_number

    @reserva_payment.update_columns(
      payment_link_id: checkout_order_number,
      updated_at: Time.current
    )
  end

  def expire_payment_if_needed!
    return unless @reserva_payment.waiting_payment? && @reserva_payment.expired?

    ReservaPaymentProcessor.call(
      reserva_payment: @reserva_payment,
      status: 'overdue',
      source: 'public_payment_link'
    )
  end

  def payment_link_unavailable?
    @reserva.canceled? ||
      @reserva_payment.canceled? ||
      @reserva_payment.overdue? ||
      @reserva_payment.expired?
  end

  def assign_payment_page_details
    @payment_paid = @reserva_payment.paid?
    @payment_open = payment_open?
    @payment_unavailable = payment_link_unavailable?
    @payment_status_label = payment_status_label(@reserva_payment.payment_status)
    @payment_link_url = @reserva_payment.payment_link_url
    @purchase_items = purchase_items
    @reservation_total = reservation_total
    @payment_due_at = @reserva_payment.due_at&.in_time_zone('America/Sao_Paulo')
    @nights_count = nights_count
  end

  def payment_open?
    @reserva_payment.waiting_payment? && !@reserva_payment.expired? && !@reserva.canceled?
  end

  def payment_status_label(status)
    {
      'waiting_payment' => 'Aguardando pagamento',
      'paid' => 'Pagamento confirmado',
      'refused' => 'Pagamento recusado',
      'canceled' => 'Link cancelado',
      'overdue' => 'Prazo vencido'
    }.fetch(status.to_s, status.to_s.humanize)
  end

  def purchase_items
    return public_booking_purchase_items if @reserva_payment.public_booking?

    admin_purchase_items
  end

  def public_booking_purchase_items
    items = [{
      name: 'Hospedagem',
      detail: stay_detail,
      quantity: 1,
      total: @reserva_payment.public_booking_daily_total
    }]

    @reserva_payment.public_booking_services.each do |service|
      items << {
        name: service['name'],
        detail: Date.parse(service['service_date'].to_s).strftime('%d/%m/%Y'),
        quantity: service['quantity'].to_i,
        total: decimal_value(service['total'])
      }
    rescue ArgumentError, TypeError
      next
    end

    items
  end

  def admin_purchase_items
    services = displayable_reserva_services
    services_total = services.sum { |reserva_service| reserva_service_total(reserva_service) }
    lodging_total = [reservation_total - services_total, 0.to_d].max

    items = [{
      name: 'Hospedagem',
      detail: stay_detail,
      quantity: 1,
      total: lodging_total
    }]

    services.each do |reserva_service|
      items << {
        name: reserva_service.service.name,
        detail: service_detail(reserva_service),
        quantity: reserva_service.quantity.to_i,
        total: reserva_service_total(reserva_service)
      }
    end

    items
  end

  def displayable_reserva_services
    @displayable_reserva_services ||= @reserva.reserva_services.includes(:service).select do |reserva_service|
      next false unless reserva_service.active?
      next false if CleaningServicesAssigner.cleaning_service?(reserva_service.service)
      next false if BreakfastServicesAssigner.included_breakfast_service?(reserva_service)
      next false if ReservaService.free_date_service?(reserva_service.service)

      true
    end
  end

  def reserva_service_total(reserva_service)
    return decimal_value(reserva_service.total_paid) if reserva_service.total_paid.present?

    unit_price = reserva_service.unit_price_paid.presence ||
                 reserva_service.service&.price_for(@reserva) ||
                 0
    decimal_value(unit_price) * reserva_service.quantity.to_i
  end

  def reservation_total
    @reservation_total ||= begin
      reserva_total = decimal_value(@reserva.total_price)
      payment_total = decimal_value(
        @reserva.reserva_payments.where.not(payment_status: 'canceled').sum(:amount)
      )
      [reserva_total, payment_total, decimal_value(@reserva_payment.amount)].max
    end
  end

  def stay_detail
    "#{@reserva.start_date.strftime('%d/%m/%Y')} a #{@reserva.end_date.strftime('%d/%m/%Y')} · #{nights_count} #{'noite'.pluralize(nights_count)}"
  end

  def service_detail(reserva_service)
    reserva_service.service_date.strftime('%d/%m/%Y')
  end

  def nights_count
    @nights_count ||= [(@reserva.end_date - @reserva.start_date).to_i, 0].max
  end

  def decimal_value(value)
    BigDecimal(value.to_s.presence || '0')
  rescue ArgumentError, TypeError
    0.to_d
  end
end
