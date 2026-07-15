class ReservaPaymentExpiry
  DEFAULT_GRACE_MINUTES = 10

  Result = Struct.new(:expired, :errors, keyword_init: true)

  def self.run(grace_minutes: nil)
    new(grace_minutes: grace_minutes).call
  end

  def initialize(grace_minutes: nil)
    @grace_minutes = positive_integer(grace_minutes || ENV['RESERVA_PAYMENT_EXPIRY_GRACE_MINUTES'], DEFAULT_GRACE_MINUTES)
    @result = Result.new(expired: 0, errors: 0)
  end

  def call
    ReservaPayment.open
                  .includes(:reserva)
                  .where('due_at < ?', @grace_minutes.minutes.ago)
                  .find_each do |reserva_payment|
      expire_payment(reserva_payment)
    end

    @result
  end

  private

  def expire_payment(reserva_payment)
    ReservaPaymentProcessor.call(
      reserva_payment: reserva_payment,
      status: 'overdue',
      source: 'expiry'
    )
    @result.expired += 1
  rescue => e
    @result.errors += 1
    Rails.logger.error("Erro ao vencer parcela de reserva #{reserva_payment.id}: #{e.message}")
  end

  def positive_integer(value, default)
    integer = value.to_i
    integer.positive? ? integer : default
  end
end
