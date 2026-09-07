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
    cancel_pending_for_removed_recipients
    return unless schedulable_reserva?

    setting = EmailAutomationSetting.current
    ReservationEmailTemplate.active.find_each do |template|
      next unless template.matches_reserva?(@reserva)
      if template.trigger_anchor == 'reservation_confirmed'
        next unless newly_confirmed_reservation?
        next unless @reserva.reservation_confirmation_email_allowed?
      end

      scheduled_at = scheduled_at_for(template)
      next if scheduled_at.blank?
      next if before_current_activation?(scheduled_at, setting)
      next if past_non_confirmation_email?(template, scheduled_at)

      recipient_emails.each do |recipient_email|
        delivery = @reserva.reservation_email_deliveries.find_or_initialize_by(
          reservation_email_template: template,
          recipient_email: recipient_email
        )
        next if delivery.sent?

        delivery.assign_attributes(
          trigger_key: template.trigger_key,
          subject: template.render_subject(@reserva),
          body: template.render_body(@reserva),
          scheduled_at: scheduled_at,
          status: 'pending',
          error_message: nil
        )
        delivery.save!
      end
    end
  end

  private

  def schedulable_reserva?
    @reserva.integration_ready? && recipient_emails.present?
  end

  def recipient_emails
    @recipient_emails ||= @reserva.reservation_email_recipient_emails
  end

  def cancel_pending_for_removed_recipients
    scope = @reserva.reservation_email_deliveries.pending

    if recipient_emails.present?
      scope = scope.where.not(recipient_email: recipient_emails)
      reason = 'E-mail removido da reserva'
    else
      reason = 'E-mail real do hóspede não informado'
    end

    scope.update_all(
      status: 'canceled',
      error_message: reason,
      updated_at: Time.current
    )
  end

  def scheduled_at_for(template)
    return Time.current if template.trigger_anchor == 'reservation_confirmed'

    template.scheduled_at_for(@reserva)
  end

  def past_non_confirmation_email?(template, scheduled_at)
    template.trigger_anchor != 'reservation_confirmed' && scheduled_at < Time.current
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
