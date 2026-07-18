class ReservationEmailDispatcher
  Result = Struct.new(:checked, :sent, :skipped, :failed, keyword_init: true)

  def self.run(limit: 50, trigger_key: nil, exclude_trigger_key: nil)
    new(limit: limit, trigger_key: trigger_key, exclude_trigger_key: exclude_trigger_key).run
  end

  def initialize(limit:, trigger_key: nil, exclude_trigger_key: nil)
    @limit = limit
    @trigger_key = trigger_key
    @exclude_trigger_key = exclude_trigger_key
    @result = Result.new(checked: 0, sent: 0, skipped: 0, failed: 0)
  end

  def run
    setting = EmailAutomationSetting.current
    return @result unless setting.enabled?

    due_deliveries.limit(@limit).includes(:reservation_email_template, reserva: [:user, { cabana: :filial }]).find_each do |delivery|
      @result.checked += 1
      process_delivery(delivery, setting)
    end

    @result
  end

  private

  def process_delivery(delivery, setting)
    if before_current_activation?(delivery, setting)
      delivery.update!(status: 'skipped', error_message: 'E-mail anterior à ativação do envio automático')
      @result.skipped += 1
      return
    end

    if delivery.reservation_email_template.blank?
      delivery.update!(status: 'skipped', error_message: 'Modelo de e-mail removido')
      @result.skipped += 1
      return
    end

    unless delivery.reserva.integration_ready?
      delivery.update!(status: 'skipped', error_message: 'Reserva não confirmada ou cancelada')
      @result.skipped += 1
      return
    end

    if delivery.trigger_key == 'reservation_confirmed' && !delivery.reserva.reservation_confirmation_email_allowed?
      delivery.update!(status: 'skipped', error_message: 'Confirmação não enviada para reserva importada')
      @result.skipped += 1
      return
    end

    recipient_email = delivery.reserva.reservation_email_recipient_email
    if recipient_email.blank?
      delivery.update!(status: 'skipped', error_message: 'E-mail real do hóspede não informado')
      @result.skipped += 1
      return
    end

    if !delivery.reservation_email_template.active?
      delivery.update!(status: 'skipped', error_message: 'Modelo de e-mail inativo')
      @result.skipped += 1
      return
    end

    refresh_delivery_content(delivery, recipient_email)
    UserMailer.reservation_automation(delivery).deliver_now
    delivery.mark_sent!
    @result.sent += 1
  rescue => e
    delivery.mark_failed!(e.message)
    @result.failed += 1
  end

  def before_current_activation?(delivery, setting)
    setting.activated_at.present? && delivery.scheduled_at < setting.activated_at
  end

  def due_deliveries
    scope = ReservationEmailDelivery.due
    scope = scope.where(trigger_key: @trigger_key) if @trigger_key.present?
    scope = scope.where.not(trigger_key: @exclude_trigger_key) if @exclude_trigger_key.present?
    scope
  end

  def refresh_delivery_content(delivery, recipient_email)
    template = delivery.reservation_email_template
    delivery.assign_attributes(
      recipient_email: recipient_email,
      subject: template.render_subject(delivery.reserva),
      body: template.render_body(delivery.reserva)
    )
    delivery.save! if delivery.changed?
  end
end
