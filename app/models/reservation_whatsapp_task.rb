class ReservationWhatsappTask < ApplicationRecord
  belongs_to :reserva, optional: true
  belongs_to :reservation_email_template, optional: true
  belongs_to :operational_service_occurrence, optional: true

  validates :trigger_key, :template_name, :message_body, :scheduled_at, :scheduled_on, presence: true
  validate :must_have_reserva_or_operational_occurrence

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

  def active_for_whatsapp?
    reservation_email_template.blank? || reservation_email_template.active?
  end

  def guest_name
    return recipient_name.to_s if operational_task?

    reserva.guest_name.presence || reserva.user&.name.to_s
  end

  def guest_phone
    return recipient_phone.to_s if operational_task?

    reserva.guest_phone.presence || reserva.user&.telephone.to_s
  end

  def cabana_name
    if recurring_maintenance_task?
      filial = operational_service_occurrence&.filial || operational_service_occurrence&.cabana&.filial
      return filial&.name.to_s
    end

    cabana = operational_task? ? operational_service_occurrence&.cabana : reserva&.cabana

    cabana&.guest_display_name.presence || cabana&.name.to_s
  end

  def reservation_label
    return 'Manutenção' if operational_task?

    reserva_id.present? ? "##{reserva_id}" : '-'
  end

  def checkin_date
    operational_task? ? operational_service_occurrence&.service_date : reserva&.start_date
  end

  def checkout_date
    operational_task? ? nil : reserva&.end_date
  end

  def operational_task?
    operational_service_occurrence_id.present?
  end

  def recurring_maintenance_task?
    operational_task? && trigger_key.to_s.start_with?('recurring_maintenance:')
  end

  private

  def must_have_reserva_or_operational_occurrence
    return if reserva_id.present? || operational_service_occurrence_id.present?

    errors.add(:base, 'Informe uma reserva ou uma manutenção operacional.')
  end
end
