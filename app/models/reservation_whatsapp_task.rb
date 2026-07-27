class ReservationWhatsappTask < ApplicationRecord
  belongs_to :reserva
  belongs_to :reservation_email_template, optional: true

  validates :trigger_key, :template_name, :message_body, :scheduled_at, :scheduled_on, presence: true

  scope :pending, -> { where(completed_at: nil) }
  scope :visible_on, lambda { |date|
    day_start = date.beginning_of_day
    next_day_start = (date + 1.day).beginning_of_day

    where('scheduled_at < ?', next_day_start)
      .where('completed_at IS NULL OR completed_at >= ?', day_start)
  }

  def completed?
    completed_at.present?
  end

  def overdue?(date = Date.current)
    !completed? && scheduled_on < date
  end

  def guest_name
    reserva.guest_name.presence || reserva.user&.name.to_s
  end

  def guest_phone
    reserva.guest_phone.presence || reserva.user&.telephone.to_s
  end

  def cabana_name
    reserva.cabana&.guest_display_name.presence || reserva.cabana&.name.to_s
  end
end
