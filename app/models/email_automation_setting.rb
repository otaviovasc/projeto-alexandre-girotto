class EmailAutomationSetting < ApplicationRecord
  DEFAULT_WHATSAPP_TASK_ALERT_EMAILS = ['flavoloski@gmail.com'].freeze

  belongs_to :paused_by, class_name: 'User', optional: true

  validates :whatsapp_task_alert_email_1,
            :whatsapp_task_alert_email_2,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            allow_blank: true

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

  def whatsapp_task_alert_emails
    configured = [
      whatsapp_task_alert_email_1,
      whatsapp_task_alert_email_2
    ].map(&:to_s).map(&:strip).reject(&:blank?).uniq

    return configured if configured.any?

    env_emails = ENV
      .fetch('WHATSAPP_TASK_ALERT_EMAILS', ENV['WHATSAPP_TASK_ALERT_EMAIL'].to_s)
      .split(/[,\s;]+/)
      .map(&:strip)
      .reject(&:blank?)
      .uniq

    env_emails.presence || DEFAULT_WHATSAPP_TASK_ALERT_EMAILS
  end
end
