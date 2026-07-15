class ReservaPendingPaymentSetup
  DEFAULT_HOLD_HOURS = 3

  def self.call(reserva:, payments_attributes:, hold_hours:)
    new(reserva: reserva, payments_attributes: payments_attributes, hold_hours: hold_hours).call
  end

  def initialize(reserva:, payments_attributes:, hold_hours:)
    @reserva = reserva
    @payments_attributes = payments_attributes
    @hold_hours = positive_decimal(hold_hours, DEFAULT_HOLD_HOURS)
  end

  def call
    normalized_rows.each do |row|
      payment = create_payment!(row)
      attach_cielo_link!(payment)
    end

    @reserva.reserva_payments.reload
  end

  private

  def normalized_rows
    rows = raw_payment_rows
    first_due_at = @hold_hours.hours.from_now
    first_amount = positive_decimal(rows.dig(1, :amount), @reserva.total_price)

    result = [{
      installment_number: 1,
      amount: first_amount,
      due_at: parse_due_at(rows.dig(1, :due_at), first_due_at)
    }]

    (2..3).each do |installment_number|
      row = rows[installment_number] || {}
      amount = positive_decimal(row[:amount], nil)
      next if amount.blank?

      due_at = parse_due_at(row[:due_at], nil)
      if due_at.blank?
        @reserva.errors.add(:base, "Informe o vencimento da #{installment_number}ª parcela.")
        raise ActiveRecord::RecordInvalid.new(@reserva)
      end

      result << {
        installment_number: installment_number,
        amount: amount,
        due_at: due_at
      }
    end

    result
  end

  def raw_payment_rows
    source = if @payments_attributes.respond_to?(:to_unsafe_h)
               @payments_attributes.to_unsafe_h
             elsif @payments_attributes.respond_to?(:to_h)
               @payments_attributes.to_h
             else
               {}
             end

    source.each_with_object({}) do |(key, value), rows|
      attrs = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
      installment_number = attrs[:installment_number].presence || attrs['installment_number'].presence || key
      installment_number = installment_number.to_i
      next unless installment_number.positive?

      rows[installment_number] = {
        amount: attrs[:amount].presence || attrs['amount'].presence,
        due_at: attrs[:due_at].presence || attrs['due_at'].presence
      }
    end
  end

  def create_payment!(row)
    @reserva.reserva_payments.create!(
      installment_number: row[:installment_number],
      amount: row[:amount],
      due_at: row[:due_at],
      payment_order_code: next_order_code(row[:installment_number])
    )
  end

  def attach_cielo_link!(payment)
    result = CieloCheckoutService.new(
      merchant_id: @reserva.cabana.filial.cielo_checkout_merchant_id_for_payments,
      order_code: payment.payment_order_code,
      items: [{
        id: "RP#{payment.id}",
        name: "Reserva ##{@reserva.id} - #{payment.installment_number}ª parcela",
        description: "Hospedagem #{@reserva.cabana.name} - #{@reserva.start_date.strftime('%d/%m')} a #{@reserva.end_date.strftime('%d/%m')}",
        unit_price: payment.amount,
        quantity: 1
      }],
      return_url: payment.public_payment_url,
      customer: {
        name: @reserva.guest_name.presence || @reserva.user.name,
        email: @reserva.user.email,
        phone: @reserva.guest_phone.presence || @reserva.user.telephone
      },
      max_installments: 1
    ).call

    payment.update!(
      payment_link_id: result['id'],
      payment_link_url: result['url']
    )
  end

  def next_order_code(installment_number)
    loop do
      code = "RP#{@reserva.id}#{installment_number}#{SecureRandom.alphanumeric(4).upcase}"
      break code.first(20) unless ReservaPayment.exists?(payment_order_code: code.first(20))
    end
  end

  def parse_due_at(value, default)
    return default if value.blank?

    parsed = Time.zone.parse(value.to_s)
    return parsed if parsed.present?

    Date.parse(value.to_s).end_of_day
  rescue ArgumentError, TypeError
    default
  end

  def positive_decimal(value, default)
    decimal = BigDecimal(value.to_s.tr(',', '.'))
    decimal.positive? ? decimal : default
  rescue ArgumentError, TypeError
    default
  end
end
