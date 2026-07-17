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
    return @result unless EmailAutomationSetting.enabled?

    ReservationEmailDelivery.due.limit(@limit).includes(:reserva, :reservation_email_template).find_each do |delivery|
      @result.checked += 1
      process_delivery(delivery)
    end

    @result
  end

  private

  def process_delivery(delivery)
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
end
