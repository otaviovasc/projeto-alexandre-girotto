class ReservationEmailDispatcher
  Result = Struct.new(:checked, :sent, :skipped, :failed, keyword_init: true)

  def self.run(limit: 50)
    new(limit: limit).run
  end

  def initialize(limit:)
    @limit = limit
    @result = Result.new(checked: 0, sent: 0, skipped: 0, failed: 0)
  end

  def run
    setting = EmailAutomationSetting.current
    return @result unless setting.enabled?

    ReservationEmailDelivery.due.limit(@limit).includes(:reserva, :reservation_email_template).find_each do |delivery|
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

    if !delivery.reservation_email_template.active?
      delivery.update!(status: 'skipped', error_message: 'Modelo de e-mail inativo')
      @result.skipped += 1
      return
    end

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
end
