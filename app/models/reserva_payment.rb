class ReservaPayment < ApplicationRecord
  belongs_to :reserva

  enum payment_status: {
    waiting_payment: 'waiting_payment',
    paid: 'paid',
    refused: 'refused',
    canceled: 'canceled',
    overdue: 'overdue'
  }

  before_validation :assign_terms_token, on: :create
  before_validation :assign_default_payment_status, on: :create

  validates :installment_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :due_at, presence: true
  validates :payment_order_code, presence: true, uniqueness: true
  validates :terms_token, presence: true, uniqueness: true

  scope :open, -> { where(payment_status: 'waiting_payment') }
  scope :expired, -> { open.where('due_at < ?', Time.current) }
  scope :overdue_installments, -> { where(payment_status: 'overdue') }

  def expired?
    waiting_payment? && due_at.present? && due_at < Time.current
  end

  def confirmation_installment?
    installment_number.to_i == 1
  end

  def terms_accepted?
    terms_accepted_at.present? ||
      reserva&.reserva_payments&.where.not(terms_accepted_at: nil)&.exists?
  end

  def terms_acceptance_display_name
    terms_acceptance_name.presence ||
      reserva&.reserva_payments&.where.not(terms_accepted_at: nil)&.order(:terms_accepted_at)&.pick(:terms_acceptance_name)
  end

  def public_payment_url
    Rails.application.routes.url_helpers.reserva_payment_url(
      token: terms_token,
      host: public_host,
      protocol: 'https'
    )
  end

  def public_booking?
    public_booking_payload.to_h['source'] == 'public_booking'
  end

  def public_booking_services
    Array(public_booking_payload.to_h['services'])
  end

  def public_booking_daily_total
    BigDecimal(public_booking_payload.to_h['daily_total'].to_s)
  rescue ArgumentError, TypeError
    0.to_d
  end

  def public_booking_services_total
    BigDecimal(public_booking_payload.to_h['services_total'].to_s)
  rescue ArgumentError, TypeError
    0.to_d
  end

  private

  def assign_default_payment_status
    self.payment_status ||= 'waiting_payment'
  end

  def assign_terms_token
    self.terms_token ||= loop do
      token = SecureRandom.urlsafe_base64(18)
      break token unless self.class.exists?(terms_token: token)
    end
  end

  def public_host
    host = ENV['PAYMENT_PUBLIC_HOST'].presence ||
           ENV['APP_HOST'].presence ||
           ENV['RENDER_EXTERNAL_HOSTNAME'].presence ||
           'villaggio-stock.onrender.com'
    host.sub(%r{\Ahttps?://}, '')
  end
end
