class ReservationWhatsappTaskReminder
  DEFAULT_RECIPIENT = ENV.fetch('WHATSAPP_TASK_ALERT_EMAIL', 'flavoloski@gmail.com')

  Result = Struct.new(:pending_count, :messages, :email_sent, :email_failed, keyword_init: true)

  def self.run(slot: :morning, date: Date.current, recipient: nil)
    new(slot: slot, date: date, recipient: recipient).run
  end

  def initialize(slot:, date:, recipient:)
    @slot = slot.to_sym
    @date = date
    @recipient = recipient.presence || DEFAULT_RECIPIENT
  end

  def run
    ReservationWhatsappTaskMaterializer.run(date: @date)

    tasks = pending_tasks
    grouped = tasks.group_by(&:template_name)
    messages = grouped.sort_by { |template_name, _| template_name.to_s }.map do |template_name, grouped_tasks|
      "🚨 (#{grouped_tasks.size}) Mensagem de #{template_name} com envio pendente"
    end
    email_sent = tasks.any? ? deliver_email(tasks, messages) : false

    mark_notified(tasks) if email_sent

    Result.new(
      pending_count: tasks.size,
      messages: messages,
      email_sent: email_sent ? 1 : 0,
      email_failed: tasks.any? && !email_sent ? 1 : 0
    )
  end

  private

  def pending_tasks
    marker_column = @slot == :morning ? :morning_notified_on : :evening_notified_on

    ReservationWhatsappTask
      .pending
      .visible_on(@date)
      .where("#{marker_column} IS NULL OR #{marker_column} < ?", @date)
      .includes(
        :reservation_email_template,
        { operational_service_occurrence: { cabana: :filial } },
        reserva: [:user, { cabana: :filial }]
      )
      .select(&:active_for_whatsapp?)
  end

  def deliver_email(tasks, messages)
    UserMailer.whatsapp_task_daily_alert(@recipient, tasks, messages, @date).deliver_now
    true
  rescue => e
    Rails.logger.error "Erro ao enviar e-mail de WhatsApp: #{e.message}"
    false
  end

  def mark_notified(tasks)
    ids = tasks.map(&:id)
    return if ids.empty?

    attrs = { updated_at: Time.current }
    attrs[@slot == :morning ? :morning_notified_on : :evening_notified_on] = @date

    ReservationWhatsappTask.where(id: ids).update_all(attrs)
  end
end
