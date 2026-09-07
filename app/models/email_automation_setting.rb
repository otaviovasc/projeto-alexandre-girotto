class EmailAutomationSetting < ApplicationRecord
  belongs_to :paused_by, class_name: 'User', optional: true

  def self.current
    first_or_create!(enabled: false)
  end

  def self.enabled?
    current.enabled?
  end

  def pause!(user = nil)
    update!(enabled: false, paused_at: Time.current, paused_by: user)
  end

  def resume!
    now = Time.current
    update!(enabled: true, activated_at: now, paused_at: nil, paused_by: nil)

    ReservationEmailDelivery.pending.where('scheduled_at < ?', now).update_all(
      status: 'skipped',
      error_message: 'E-mail anterior à ativação do envio automático',
      updated_at: now
    )
  end
end
