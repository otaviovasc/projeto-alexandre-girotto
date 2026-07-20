class PublicBookingServicesMaterializer
  def self.call(reserva_payment)
    new(reserva_payment).call
  end

  def initialize(reserva_payment)
    @reserva_payment = reserva_payment
    @reserva = reserva_payment.reserva
  end

  def call
    return [] unless @reserva_payment.public_booking?
    return [] if @reserva_payment.public_booking_services.blank?
    return existing_services.to_a if existing_services.exists?

    created_services = []

    ReservaService.transaction do
      @reserva_payment.public_booking_services.each do |item|
        service = Service.find_by(id: item['service_id'])
        next if service.blank?

        quantity = positive_integer(item['quantity'], 1)
        unit_price = positive_decimal(item['unit_price'], service.price_for(@reserva) || 0)

        created_services << @reserva.reserva_services.create!(
          service: service,
          quantity: quantity,
          service_date: Date.parse(item['service_date'].to_s),
          status: 'active',
          payment_status: 'paid',
          payment_link_id: @reserva_payment.payment_link_id,
          payment_link_url: @reserva_payment.payment_link_url,
          payment_order_code: @reserva_payment.payment_order_code,
          unit_price_paid: unit_price,
          total_paid: unit_price * quantity,
          paid_at: @reserva_payment.paid_at || Time.current,
          observation: item['observation'].presence,
          purchased_after_service_deadline: false
        )
      end
    end

    created_services
  end

  private

  def existing_services
    @reserva.reserva_services.where(payment_order_code: @reserva_payment.payment_order_code)
  end

  def positive_integer(value, default)
    integer = value.to_i
    integer.positive? ? integer : default
  end

  def positive_decimal(value, default)
    decimal = BigDecimal(value.to_s.tr(',', '.'))
    decimal.positive? ? decimal : default
  rescue ArgumentError, TypeError
    default
  end
end
