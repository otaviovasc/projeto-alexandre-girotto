class ReservationEmailScheduler
  def self.schedule_for_reserva(reserva)
    new(reserva).schedule
  end

  def self.cancel_pending_for_reserva(reserva, reason: 'Reserva cancelada')
    reserva.reservation_email_deliveries.pending.update_all(
      status: 'canceled',
      error_message: reason,
      updated_at: Time.current
    )
  end

  def initialize(reserva)
    @reserva = reserva
  end

  def schedule
    ReservationEmailTemplate.ensure_defaults!
    return cancel_pending('Reserva cancelada') if @reserva.canceled?
    return unless schedulable_reserva?

    setting = EmailAutomationSetting.current
    ReservationEmailTemplate.active.find_each do |template|
      next unless template.matches_reserva?(@reserva)
      next if template.trigger_anchor == 'reservation_confirmed' && !newly_confirmed_reservation?

      scheduled_at = scheduled_at_for(template)
      next if scheduled_at.blank?
      next if before_current_activation?(scheduled_at, setting)

      delivery = @reserva.reservation_email_deliveries.find_or_initialize_by(
        reservation_email_template: template
      )
      next if delivery.sent?

      delivery.assign_attributes(
        trigger_key: template.trigger_key,
        recipient_email: @reserva.user.email,
        subject: template.render_subject(@reserva),
        body: template.render_body(@reserva),
        scheduled_at: scheduled_at,
        status: 'pending',
        error_message: nil
      )
      delivery.save!
    end
  end

  private

  def schedulable_reserva?
    @reserva.integration_ready? && @reserva.user&.email.present?
  end

  def scheduled_at_for(template)
    return Time.current if template.trigger_anchor == 'reservation_confirmed'

    template.scheduled_at_for(@reserva)
  end

  def newly_confirmed_reservation?
    payment_status_change = @reserva.previous_changes['payment_status']
    availability_change = @reserva.previous_changes['blocks_availability']

    (payment_status_change.present? && payment_status_change.last == 'paid') ||
      (availability_change.present? && availability_change.last == true && @reserva.paid?)
  end

  def before_current_activation?(scheduled_at, setting)
    setting.activated_at.present? && scheduled_at < setting.activated_at
  end

  def cancel_pending(reason)
    self.class.cancel_pending_for_reserva(@reserva, reason: reason)
  end
end
