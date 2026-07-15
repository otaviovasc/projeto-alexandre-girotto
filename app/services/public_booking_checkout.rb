require 'bigdecimal'
require 'uri'

class PublicBookingCheckout
  include ActiveModel::Model

  HOLD_MINUTES = 15
  MAX_INSTALLMENTS = 6
  TEST_DAILY_RATE = BigDecimal('1')
  TEST_DAILY_RATE_DATES = [
    Date.new(2027, 7, 15),
    Date.new(2027, 7, 16)
  ].freeze

  attr_reader :reserva, :reserva_payment

  def initialize(attributes = {})
    super()
    @params = attributes.fetch(:params, {})
    @request = attributes.fetch(:request, nil)
  end

  def call
    load_inputs
    validate_inputs
    return false if errors.any?

    Reserva.transaction do
      @cabana.lock!
      @user = find_or_create_user!
      @reserva = create_reserva!
      @reserva_payment = create_reserva_payment!
    end

    attach_cielo_link!
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    cancel_created_reserva('Erro ao criar checkout publico.') if @reserva&.persisted?
    false
  rescue CieloCheckoutService::Error => e
    errors.add(:base, e.message)
    cancel_created_reserva('Erro ao criar checkout na Cielo.')
    false
  rescue => e
    Rails.logger.error("Erro inesperado no checkout publico: #{e.message}")
    errors.add(:base, 'Nao foi possivel iniciar a compra. Tente novamente.')
    cancel_created_reserva('Erro inesperado ao criar checkout publico.')
    false
  end

  private

  def load_inputs
    @cabana = Cabana.includes(:filial).find_by(id: @params[:cabana_id])
    @start_date = parse_date(@params[:start_date])
    @end_date = parse_date(@params[:end_date])
    @guest_name = @params[:guest_name].to_s.squish
    @guest_email = @params[:guest_email].to_s.strip.downcase
    @guest_phone = @params[:guest_phone].to_s.gsub(/\D/, '')
    @terms_accepted = ActiveModel::Type::Boolean.new.cast(@params[:terms_accepted])
    @selected_services = normalized_service_items
  end

  def validate_inputs
    errors.add(:base, 'Selecione uma cabana.') if @cabana.blank?
    errors.add(:base, 'Informe a data de entrada.') if @start_date.blank?
    errors.add(:base, 'Informe a data de saída.') if @end_date.blank?
    errors.add(:base, 'A data de saída precisa ser depois da entrada.') if @start_date.present? && @end_date.present? && @end_date <= @start_date
    errors.add(:base, 'Informe nome e sobrenome do responsável pela reserva.') if @guest_name.split(/\s+/).size < 2
    errors.add(:base, 'Informe um e-mail válido.') unless @guest_email.match?(URI::MailTo::EMAIL_REGEXP)
    errors.add(:base, 'Informe um WhatsApp válido.') unless @guest_phone.length.between?(8, 15)
    errors.add(:base, 'Confirme o aceite dos termos para continuar.') unless @terms_accepted
    errors.add(:base, 'Serviços só podem ser comprados com mais de 10 dias de antecedência.') if @selected_services.any? && !services_available?
    validate_selected_services
  end

  def validate_selected_services
    return if @cabana.blank?

    @selected_services.each do |item|
      service = item[:service]
      errors.add(:base, "Serviço inválido: #{item[:service_id]}") if service.blank?
      errors.add(:base, "#{service.name} não pertence à filial da cabana.") if service.present? && service.filial_id != @cabana.filial_id
      errors.add(:base, "#{service.name} não está disponível para compra online.") if service.present? && service.show_in_marketplace == false
      errors.add(:base, "#{service.name} não está disponível para compra online.") if service.present? && internal_public_service?(service)
      errors.add(:base, "Informe a data de #{service.name}.") if service.present? && item[:service_date].blank?
      next if service.blank? || item[:service_date].blank? || @start_date.blank? || @end_date.blank?

      unless item[:service_date].between?(@start_date, @end_date)
        errors.add(:base, "#{service.name} precisa ficar entre a entrada e a saída.")
      end
    end
  end

  def find_or_create_user!
    user = User.find_or_initialize_by(email: @guest_email)
    user.name = @guest_name if user.name.blank? || user.name.to_s.match?(/\A(?:Airbnb|Booking|Holmy)\z/i)
    user.filial ||= @cabana.filial
    assign_phone_if_available(user)

    if user.new_record?
      password = SecureRandom.urlsafe_base64(18)
      user.password = password
      user.password_confirmation = password
      user.role ||= :client
      user.partner = false if user.partner.nil?
      user.skip_welcome_email = true
    end

    user.save!
    user
  end

  def assign_phone_if_available(user)
    return if @guest_phone.blank?
    return if user.telephone == @guest_phone
    return if User.where(telephone: @guest_phone).where.not(id: user.id).exists?

    user.telephone = @guest_phone
  end

  def create_reserva!
    reserva = Reserva.new(
      cabana: @cabana,
      user: @user,
      start_date: @start_date,
      end_date: @end_date,
      payment_status: 'waiting_payment',
      blocks_availability: true,
      payment_expires_at: due_at,
      observation: 'Sistema - Site oficial',
      origem: 'sistema',
      guest_name: @guest_name,
      guest_phone: @guest_phone,
      service_max_installments: MAX_INSTALLMENTS
    )

    reserva.total_price = total_amount
    reserva.save!
    reserva
  end

  def create_reserva_payment!
    @reserva.reserva_payments.create!(
      installment_number: 1,
      amount: total_amount,
      due_at: due_at,
      payment_order_code: next_order_code,
      terms_accepted_at: Time.current,
      terms_acceptance_name: @guest_name,
      terms_acceptance_ip: @request&.remote_ip,
      terms_acceptance_user_agent: @request&.user_agent,
      public_booking_payload: public_booking_payload
    )
  end

  def attach_cielo_link!
    result = CieloCheckoutService.new(
      merchant_id: @cabana.filial.cielo_checkout_merchant_id_for_payments,
      order_code: @reserva_payment.payment_order_code,
      items: cielo_items,
      return_url: public_booking_confirmation_url,
      customer: {
        name: @guest_name,
        email: @guest_email,
        phone: @guest_phone
      },
      soft_descriptor: 'VILLAGGIO',
      max_installments: MAX_INSTALLMENTS
    ).call

    @reserva_payment.update!(
      payment_link_id: result['id'],
      payment_link_url: result['url']
    )
  end

  def total_amount
    @total_amount ||= daily_total + services_total
  end

  def daily_total
    @daily_total ||= begin
      reservation = Reserva.new(cabana: @cabana, start_date: @start_date, end_date: @end_date)
      calculator = PriceCalculator.new(reservation)

      (@start_date...@end_date).sum do |date|
        TEST_DAILY_RATE_DATES.include?(date) ? TEST_DAILY_RATE : calculator.price_for_day(date)
      end
    end
  end

  def services_total
    @services_total ||= @selected_services.sum { |item| item[:unit_price] * item[:quantity] }
  end

  def normalized_service_items
    raw_items = @params[:service_items]
    return [] if raw_items.blank?

    raw_items.to_h.filter_map do |service_id, attrs|
      attrs = attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs.to_h
      next unless ActiveModel::Type::Boolean.new.cast(attrs[:selected].presence || attrs['selected'])

      service = Service.find_by(id: service_id)
      quantity = positive_integer(attrs[:quantity].presence || attrs['quantity'], 1)
      unit_price = service&.price || 0

      {
        service_id: service_id,
        service: service,
        service_date: parse_date(attrs[:service_date].presence || attrs['service_date']),
        quantity: quantity,
        unit_price: unit_price,
        observation: attrs[:observation].presence || attrs['observation'].presence
      }
    end
  end

  def internal_public_service?(service)
    CleaningServicesAssigner.cleaning_service?(service) ||
      ReservaService.free_date_service?(service)
  end

  def public_booking_payload
    {
      source: 'public_booking',
      daily_total: decimal_string(daily_total),
      services_total: decimal_string(services_total),
      customer: {
        name: @guest_name,
        email: @guest_email,
        phone: @guest_phone
      },
      services: @selected_services.map do |item|
        {
          service_id: item[:service].id,
          name: item[:service].name,
          service_date: item[:service_date].to_s,
          quantity: item[:quantity],
          unit_price: decimal_string(item[:unit_price]),
          total: decimal_string(item[:unit_price] * item[:quantity]),
          observation: item[:observation]
        }
      end
    }
  end

  def cielo_items
    items = [{
      id: "RES#{@reserva.id}",
      name: "Hospedagem #{@cabana.name}",
      description: "Reserva ##{@reserva.id} - #{@start_date.strftime('%d/%m/%Y')} a #{@end_date.strftime('%d/%m/%Y')}",
      unit_price: daily_total,
      quantity: 1
    }]

    @selected_services.each do |item|
      service = item[:service]
      items << {
        id: "SV#{service.id}",
        name: "#{service.name} - #{item[:service_date].strftime('%d/%m')}",
        description: "#{service.name} - Reserva ##{@reserva.id}",
        unit_price: item[:unit_price],
        quantity: item[:quantity]
      }
    end

    items
  end

  def due_at
    @due_at ||= HOLD_MINUTES.minutes.from_now
  end

  def services_available?
    @start_date.present? && Date.current < (@start_date - Reserva::SERVICE_PURCHASE_BLOCK_DAYS_BEFORE_CHECKIN.days)
  end

  def public_booking_confirmation_url
    Rails.application.routes.url_helpers.public_booking_confirmation_url(
      token: @reserva_payment.terms_token,
      host: callback_host,
      protocol: callback_protocol
    )
  end

  def callback_host
    @request&.host_with_port.presence || ENV['APP_HOST'].presence || ENV['RENDER_EXTERNAL_HOSTNAME'].presence || 'villaggio-stock.onrender.com'
  end

  def callback_protocol
    @request&.protocol.presence || 'https://'
  end

  def next_order_code
    loop do
      code = "RP#{@reserva.id}1#{SecureRandom.alphanumeric(4).upcase}".first(20)
      break code unless ReservaPayment.exists?(payment_order_code: code)
    end
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def positive_integer(value, default)
    integer = value.to_i
    integer.positive? ? integer : default
  end

  def decimal_string(value)
    BigDecimal(value.to_s).to_s('F')
  rescue ArgumentError, TypeError
    '0'
  end

  def cancel_created_reserva(reason)
    @reserva.cancel_for_operations!(by: nil, reason: reason)
  rescue => e
    Rails.logger.error("Erro ao cancelar pre-reserva publica ##{@reserva&.id}: #{e.message}")
  end
end
