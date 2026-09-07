class ReservationWhatsappTaskReminder
  DEFAULT_RECIPIENT = 'flavoloski@gmail.com'.freeze

  Result = Struct.new(:pending_count, :messages, :email_sent, :email_failed, keyword_init: true)

  def self.run(slot: :morning, date: Date.current, recipient: nil)
    new(slot: slot, date: date, recipient: recipient).run
  end

  def initialize(slot:, date:, recipient:)
    @slot = slot.to_sym
    @date = date
    @recipients = Array(recipient.presence || EmailAutomationSetting.current.whatsapp_task_alert_emails)
      .flat_map { |value| value.to_s.split(/[,\s;]+/) }
      .map(&:strip)
      .reject(&:blank?)
      .uniq
    @recipients = [DEFAULT_RECIPIENT] if @recipients.empty?
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

    result = { sent: 0, failed: 0 }
    @recipients.each do |recipient|
      begin
        UserMailer.whatsapp_task_daily_alert(recipient, tasks, messages, @date).deliver_now
        result[:sent] += 1
      rescue => e
        Rails.logger.error "Erro ao enviar e-mail de WhatsApp para #{recipient}: #{e.message}"
        result[:failed] += 1
      end
    end
    result
  end

  def mark_notified(tasks)
    ids = tasks.map(&:id)
    return if ids.empty?

    attrs = { updated_at: Time.current }
    attrs[@slot == :morning ? :morning_notified_on : :evening_notified_on] = @date

    ReservationWhatsappTask.where(id: ids).update_all(attrs)
  end
end
