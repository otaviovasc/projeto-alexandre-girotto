class ReservationEmailDelivery < ApplicationRecord
  belongs_to :reserva
  belongs_to :reservation_email_template, optional: true

  enum status: {
    pending: 'pending',
    sent: 'sent',
    skipped: 'skipped',
    failed: 'failed',
    canceled: 'canceled'
  }

  validates :trigger_key, :recipient_email, :subject, :body, :scheduled_at, presence: true

  scope :due, -> { pending.where('scheduled_at <= ?', Time.current).order(:scheduled_at, :id) }

  def mark_sent!
    update!(status: 'sent', sent_at: Time.current, error_message: nil)
  end

  def mark_failed!(message)
    update!(status: 'failed', error_message: message.to_s.first(500))
  end
end
