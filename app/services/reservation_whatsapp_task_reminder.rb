class ReservationWhatsappTaskReminder
  Result = Struct.new(:pending_count, :messages, :push_sent, :push_failed, keyword_init: true)

  def self.run(slot:, date: Date.current)
    new(slot: slot, date: date).run
  end

  def initialize(slot:, date:)
    @slot = slot.to_sym
    @date = date
  end

  def run
    ReservationWhatsappTaskMaterializer.run(date: @date)

    tasks = pending_tasks
    grouped = tasks.group_by(&:template_name)
    messages = grouped.map do |template_name, grouped_tasks|
      "🚨 (#{grouped_tasks.size}) Mensagem de #{template_name} com envio pendente"
    end
    push_result = notify_pending_groups(grouped)

    mark_notified(tasks) if messages.any?

    Result.new(
      pending_count: tasks.size,
      messages: messages,
      push_sent: push_result.fetch(:sent),
      push_failed: push_result.fetch(:failed)
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
      .select { |task| task.reservation_email_template&.active? }
  end

  def mark_notified(tasks)
    ids = tasks.map(&:id)
    return if ids.empty?

    attrs = { updated_at: Time.current }
    attrs[@slot == :morning ? :morning_notified_on : :evening_notified_on] = @date

    ReservationWhatsappTask.where(id: ids).update_all(attrs)
  end

  def notify_pending_groups(grouped)
    grouped.each_with_object({ sent: 0, failed: 0 }) do |(template_name, grouped_tasks), result|
      title = "🚨 (#{grouped_tasks.size}) Mensagem de #{template_name} com envio pendente"
      response = WhatsappTaskPushNotifier.deliver(
        title: title,
        body: 'Abra o aplicativo da Flavia para copiar e marcar o envio.',
        tag: "whatsapp-task-#{@slot}-#{@date}-#{template_name.parameterize}",
        url: ENV['WHATSAPP_TASKS_URL']
      )

      if response.sent
        result[:sent] += 1
      else
        result[:failed] += 1
        Rails.logger.warn("Push WhatsApp não enviado: #{response.status} #{response.message}")
      end
    end
  end
end
