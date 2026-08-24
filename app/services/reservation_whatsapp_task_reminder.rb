class ReservationWhatsappTaskReminder
  DEFAULT_RECIPIENT = 'flavoloski@gmail.com'.freeze

  Result = Struct.new(:pending_count, :messages, :email_sent, :email_failed, keyword_init: true)

  def self.run(slot: :morning, date: Date.current, recipient: nil)
    new(slot: slot, date: date, recipient: recipient).run
  end

  def initialize(slot:, date:, recipient:)
    @slot = slot.to_sym
    @date = date
    @recipient = recipient.presence || ENV['WHATSAPP_TASK_ALERT_EMAIL'].presence || DEFAULT_RECIPIENT
  end

  def run
    ReservationWhatsappTaskMaterializer.run(date: @date)

    tasks = pending_tasks
    grouped = tasks.group_by(&:template_name)
    messages = grouped.sort_by { |template_name, _| template_name.to_s }.map do |template_name, grouped_tasks|
      "🚨 (#{grouped_tasks.size}) Mensagem de #{template_name} com envio pendente"
    end
    email_result = deliver_email(tasks, messages)

    mark_notified(tasks) if email_result.fetch(:sent).positive?

    Result.new(
      pending_count: tasks.size,
      messages: messages,
      email_sent: email_result.fetch(:sent),
      email_failed: email_result.fetch(:failed)
    )
  end

  private

  def pending_tasks
    marker_column = @slot == :morning ? :morning_notified_on : :evening_notified_on

    ReservationWhatsappTask
      .pending
      .visible_on(@date)
      .where("#{marker_column} IS NULL OR #{marker_column} < ?", @date)
      .includes(:reservation_email_template, reserva: [:user, { cabana: :filial }])
      .select(&:active_for_whatsapp?)
  end

  def deliver_email(tasks, messages)
    return { sent: 0, failed: 0 } if tasks.empty?

    UserMailer.whatsapp_task_daily_alert(@recipient, tasks, messages, @date).deliver_now
    { sent: 1, failed: 0 }
  rescue => e
    Rails.logger.error "Erro ao enviar e-mail de WhatsApp para #{@recipient}: #{e.message}"
    { sent: 0, failed: 1 }
  end

  def mark_notified(tasks)
    ids = tasks.map(&:id)
    return if ids.empty?

    attrs = { updated_at: Time.current }
    attrs[@slot == :morning ? :morning_notified_on : :evening_notified_on] = @date

    ReservationWhatsappTask.where(id: ids).update_all(attrs)
  end
end
