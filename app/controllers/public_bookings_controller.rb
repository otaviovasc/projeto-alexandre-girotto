class PublicBookingsController < ApplicationController
  ONLINE_BOOKING_MIN_LEAD_HOURS = 48

  layout 'portal_reserva'

  skip_before_action :authenticate_user!
  before_action :load_public_catalog, only: [:new, :create]
  before_action :set_reserva_payment, only: [:confirmation, :status]

  def new
    @booking_values = prefilled_booking_values
  end

  def create
    if too_close_for_online_booking?
      assign_too_close_booking_details
      render :too_close, status: :ok
      return
    end

    checkout = PublicBookingCheckout.new(params: booking_params.to_h.with_indifferent_access, request: request)

    if checkout.call
      redirect_to public_booking_confirmation_path(token: checkout.reserva_payment.terms_token), status: :see_other
    else
      @booking_values = booking_params.to_h
      @errors = checkout.errors.full_messages
      render :new, status: :unprocessable_entity
    end
  end

  def quote
    cabana = Cabana.find_by(id: params[:cabana_id])
    start_date = parse_date_param(params[:start_date])
    end_date = parse_date_param(params[:end_date])

    if cabana.blank?
      render json: { ok: false, error: 'Selecione uma cabana.' }, status: :unprocessable_entity
      return
    end

    if start_date.blank? || end_date.blank? || end_date <= start_date
      render json: { ok: false, error: 'Informe entrada e saída válidas.' }, status: :unprocessable_entity
      return
    end

    quote = OfficialSitePricing.new.quote(cabana: cabana, start_date: start_date, end_date: end_date)

    unless quote[:meets_minimum]
      render json: { ok: false, error: quote[:minimum_message] }, status: :unprocessable_entity
      return
    end

    render json: {
      ok: true,
      cabana_name: cabana.name,
      start_date: start_date.to_s,
      end_date: end_date.to_s,
      nights: quote[:nights_count],
      daily_total: quote[:stay_total].to_f
    }
  rescue OfficialSitePricing::Error => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  def confirmation
    refresh_payment_status!
    assign_confirmation_details
  end

  def status
    refresh_payment_status!

    render json: {
      paid: @reserva_payment.paid?,
      open: payment_open?,
      status: @reserva_payment.payment_status,
      status_label: payment_status_label(@reserva_payment.payment_status)
    }
  end

  private

  def booking_params
    params.require(:booking).permit(
      :cabana_id,
      :start_date,
      :end_date,
      :guest_name,
      :guest_email,
      :guest_phone,
      :terms_accepted,
      service_items: {}
    )
  end

  def load_public_catalog
    @cabanas = Cabana.includes(:filial).order(:name)
    @services = Service.includes(:filial)
                       .where(show_in_marketplace: [true, nil])
                       .order(:name)
                       .reject { |service| internal_public_service?(service) }
    @service_prices = public_service_prices(@services)
    @public_booking_whatsapp_by_cabana = @cabanas.each_with_object({}) do |cabana, numbers|
      numbers[cabana.id.to_s] = whatsapp_number_for(cabana.filial)
    end
  end

  def internal_public_service?(service)
    CleaningServicesAssigner.cleaning_service?(service) ||
      ReservaService.free_date_service?(service)
  end

  def set_reserva_payment
    @reserva_payment = ReservaPayment
                         .includes(reserva: [:user, { cabana: :filial }, { reserva_services: :service }])
                         .find_by!(terms_token: params[:token])
    @reserva = @reserva_payment.reserva
  end

  def refresh_payment_status!
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
    transaction, _lookup_source = CieloCheckoutService::TransactionQuery.new(
      client_id: filial.cielo_checkout_client_id_for_payments,
      client_secret: filial.cielo_checkout_client_secret_for_payments
    ).find_by_best_identifier(
      order_number: @reserva_payment.payment_order_code,
      checkout_order_number: @reserva_payment.payment_link_id
    )

    status = CieloCheckoutService.payment_status_from_transaction(transaction)
    return if status.blank?

    checkout_order_number = transaction['checkoutOrderNumber'].presence ||
                            transaction['checkout_order_number'].presence ||
                            @reserva_payment.payment_link_id
    remember_cielo_checkout_order_number(checkout_order_number)

    PaymentStatusProcessor.call(
      identifiers: [@reserva_payment.payment_order_code, @reserva_payment.payment_link_id, checkout_order_number],
      status: status
    )
  rescue CieloCheckoutService::Error => e
    Rails.logger.warn("Unable to sync public booking Cielo status: #{e.message}")
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
      source: 'public_booking'
    )
  end

  def assign_confirmation_details
    @payment_paid = @reserva_payment.paid?
    @payment_open = payment_open?
    @payment_status_label = payment_status_label(@reserva_payment.payment_status)
    @payment_link_url = @reserva_payment.payment_link_url
    @purchase_items = purchase_items
    @summary_text = public_booking_summary_text
    @whatsapp_url = public_booking_whatsapp_url
  end

  def payment_open?
    @reserva_payment.waiting_payment? && !@reserva_payment.expired? && !@reserva.canceled?
  end

  def purchase_items
    items = [{
      name: 'Hospedagem',
      detail: "#{@reserva.start_date.strftime('%d/%m/%Y')} a #{@reserva.end_date.strftime('%d/%m/%Y')}",
      quantity: 1,
      total: @reserva_payment.public_booking_daily_total
    }]

    if materialized_public_booking_services.any?
      materialized_public_booking_services.each do |reserva_service|
        items << {
          name: reserva_service.service&.name || 'Serviço',
          detail: reserva_service.service_date.strftime('%d/%m/%Y'),
          quantity: reserva_service.quantity.to_i,
          total: reserva_service_total(reserva_service)
        }
      end
    else
      @reserva_payment.public_booking_services.each do |service|
        items << {
          name: service['name'],
          detail: public_booking_service_detail(service),
          quantity: service['quantity'].to_i,
          total: BigDecimal(service['total'].to_s)
        }
      end
    end

    items
  end

  def payment_status_label(status)
    {
      'waiting_payment' => 'Aguardando pagamento',
      'paid' => 'Pagamento confirmado',
      'refused' => 'Pagamento recusado',
      'canceled' => 'Pagamento cancelado',
      'overdue' => 'Prazo vencido'
    }.fetch(status.to_s, status.to_s.humanize)
  end

  def public_booking_summary_text
    lines = [
      "Olá! Acabei de confirmar minha reserva pelo site oficial.",
      "",
      "Reserva: ##{@reserva.id}",
      "Nome: #{@reserva.guest_name.presence || @reserva.user.name}",
      "Cabana: #{@reserva.cabana.guest_display_name}",
      "Entrada: #{@reserva.start_date.strftime('%d/%m/%Y')}",
      "Saída: #{@reserva.end_date.strftime('%d/%m/%Y')}",
      "Total: #{helpers.number_to_currency(@reserva_payment.amount, unit: 'R$ ', separator: ',', delimiter: '.')}"
    ]

    service_lines = if materialized_public_booking_services.any?
                      materialized_public_booking_services.map do |reserva_service|
                        "- #{reserva_service.service&.name || 'Serviço'} - #{reserva_service.service_date.strftime('%d/%m/%Y')} (#{reserva_service.quantity}x)"
                      end
                    else
                      @reserva_payment.public_booking_services.map do |service|
                        date_text = ActiveModel::Type::Boolean.new.cast(service['date_pending']) ? 'data a definir no menu de serviços' : public_booking_service_detail(service)
                        "- #{service['name']} - #{date_text} (#{service['quantity']}x)"
                      end.compact
                    end

    if service_lines.any?
      lines << ""
      lines << "Serviços:"
      lines.concat(service_lines)
    end

    lines.join("\n")
  end

  def public_booking_whatsapp_url
    number = whatsapp_number_for(@reserva.cabana.filial)
    encoded_text = ERB::Util.url_encode(@summary_text)

    if number.present?
      "https://wa.me/#{number}?text=#{encoded_text}"
    else
      "https://wa.me/?text=#{encoded_text}"
    end
  end

  def public_booking_service_detail(service)
    return 'Data a definir no menu de serviços' if ActiveModel::Type::Boolean.new.cast(service['date_pending'])

    Date.parse(service['service_date'].to_s).strftime('%d/%m/%Y')
  rescue ArgumentError, TypeError
    'Data a definir no menu de serviços'
  end

  def materialized_public_booking_services
    @materialized_public_booking_services ||= @reserva.reserva_services
                                                    .includes(:service)
                                                    .where(payment_order_code: @reserva_payment.payment_order_code)
                                                    .order(:service_date, :id)
                                                    .to_a
  end

  def reserva_service_total(reserva_service)
    return BigDecimal(reserva_service.total_paid.to_s) if reserva_service.total_paid.present?

    unit_price = reserva_service.unit_price_paid.presence ||
                 reserva_service.service&.price_for(@reserva) ||
                 0
    BigDecimal(unit_price.to_s) * reserva_service.quantity.to_i
  rescue ArgumentError, TypeError
    0.to_d
  end

  def whatsapp_number_for(filial)
    suffix = if I18n.transliterate(filial&.name.to_s).upcase.include?('BRAUNA')
               'BRAUNA'
             else
               'SERRA'
             end

    ENV["PUBLIC_BOOKING_WHATSAPP_#{suffix}"].presence || ENV['PUBLIC_BOOKING_WHATSAPP_DEFAULT']
  end

  def parse_date_param(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def too_close_for_online_booking?
    cabana = Cabana.includes(:filial).find_by(id: booking_params[:cabana_id])
    start_date = parse_date_param(booking_params[:start_date])

    cabana.present? && start_date.present? && start_date.beginning_of_day < ONLINE_BOOKING_MIN_LEAD_HOURS.hours.from_now
  end

  def assign_too_close_booking_details
    @cabana = Cabana.includes(:filial).find_by(id: booking_params[:cabana_id])
    @start_date = parse_date_param(booking_params[:start_date])
    @end_date = parse_date_param(booking_params[:end_date])
    @guest_name = booking_params[:guest_name].to_s.squish
    @selected_service_lines = selected_booking_service_lines
    @whatsapp_url = too_close_whatsapp_url
  end

  def too_close_whatsapp_url
    number = whatsapp_number_for(@cabana&.filial)
    encoded_text = ERB::Util.url_encode(too_close_whatsapp_message)

    if number.present?
      "https://wa.me/#{number}?text=#{encoded_text}"
    else
      "https://wa.me/?text=#{encoded_text}"
    end
  end

  def too_close_whatsapp_message
    lines = [
      "Olá! Quero verificar uma reserva de última hora pelo site oficial.",
      "",
      ("Nome: #{@guest_name}" if @guest_name.present?),
      ("Cabana: #{@cabana.name}" if @cabana.present?),
      ("Entrada: #{@start_date.strftime('%d/%m/%Y')}" if @start_date.present?),
      ("Saída: #{@end_date.strftime('%d/%m/%Y')}" if @end_date.present?)
    ]

    if @selected_service_lines.present?
      lines << ""
      lines << "Serviços desejados:"
      lines.concat(@selected_service_lines)
    end

    lines.compact.join("\n")
  end

  def selected_booking_service_lines
    raw_items = booking_params[:service_items]
    return [] if raw_items.blank?

    services_by_id = @services.index_by { |service| service.id.to_s }

    raw_items.to_h.filter_map do |service_id, attrs|
      attrs = attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs.to_h
      next unless ActiveModel::Type::Boolean.new.cast(attrs[:selected].presence || attrs['selected'])

      service = services_by_id[service_id.to_s] || Service.find_by(id: service_id)
      next if service.blank?

      service_date = parse_date_param(attrs[:service_date].presence || attrs['service_date'])
      quantity = attrs[:quantity].presence || attrs['quantity'].presence || 1
      date_text = service_date.present? ? " em #{service_date.strftime('%d/%m/%Y')}" : ""

      "- #{service.name}#{date_text} (#{quantity.to_i.positive? ? quantity.to_i : 1}x)"
    end
  end

  def prefilled_booking_values
    cabana = public_prefill_cabana
    start_date = parse_date_param(params[:start_date])
    end_date = parse_date_param(params[:end_date])
    values = {}

    values['cabana_id'] = cabana.id.to_s if cabana.present?
    values['start_date'] = start_date.to_s if start_date.present?
    values['end_date'] = end_date.to_s if end_date.present?

    service_items = public_prefill_service_items(cabana, start_date)
    values['service_items'] = service_items if service_items.present?

    values
  end

  def public_prefill_cabana
    return Cabana.find_by(id: params[:cabana_id]) if params[:cabana_id].present?
    return if params[:cabana].blank?

    target_cabana = normalize_public_booking_cabana(params[:cabana])
    target_filial = normalize_public_booking_text(params[:filial])

    Cabana.includes(:filial).find do |cabana|
      normalized_name = normalize_public_booking_cabana(cabana.name)
      normalized_filial = normalize_public_booking_text(cabana.filial&.name)
      name_matches = normalized_name.start_with?(target_cabana) || normalized_name.include?(target_cabana)
      filial_matches = target_filial.blank? || normalized_filial.include?(target_filial) || target_filial.include?(normalized_filial)

      name_matches && filial_matches
    end
  end

  def public_prefill_service_items(cabana, start_date)
    return {} if cabana.blank? || params[:services].blank?

    parsed_services = JSON.parse(params[:services].to_s)
    return {} unless parsed_services.is_a?(Array)

    parsed_services.each_with_object({}) do |service_payload, result|
      service_name = service_payload['name'].to_s
      quantity = service_payload['quantity'].presence || service_payload['qty'].presence || 1
      service = public_prefill_service(cabana, service_name)
      next if service.blank?

      result[service.id.to_s] = {
        'selected' => '1',
        'service_date' => start_date&.to_s,
        'quantity' => quantity.to_i.positive? ? quantity.to_i : 1
      }
    end
  rescue JSON::ParserError, TypeError
    {}
  end

  def public_prefill_service(cabana, service_name)
    target_service = normalize_public_booking_text(service_name)
    return if target_service.blank?

    @services.find do |service|
      next false unless service.filial_id == cabana.filial_id

      normalized_name = normalize_public_booking_text(service.name)
      normalized_name == target_service || normalized_name.include?(target_service) || target_service.include?(normalized_name)
    end
  end

  def normalize_public_booking_text(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, ' ')
        .squish
  end

  def normalize_public_booking_cabana(value)
    normalize_public_booking_text(value).sub(/\Avilla vita\b/, 'vita')
  end

  def public_service_prices(services)
    pricing = OfficialSitePricing.new

    services.each_with_object({}) do |service, prices|
      prices[service.id] = pricing.service_price(service: service, filial: service.filial) || service.price
    end
  rescue OfficialSitePricing::Error => e
    Rails.logger.warn("Unable to load official service prices for public booking: #{e.message}")
    services.each_with_object({}) { |service, prices| prices[service.id] = service.price }
  end
end
