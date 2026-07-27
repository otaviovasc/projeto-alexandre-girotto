class ReservationWhatsappTaskReminder
  Result = Struct.new(:pending_count, :messages, keyword_init: true)

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
    messages = tasks.group_by(&:template_name).map do |template_name, grouped_tasks|
      "🚨 (#{grouped_tasks.size}) Mensagem de #{template_name} com envio pendente"
    end

    mark_notified(tasks) if messages.any?

    Result.new(pending_count: tasks.size, messages: messages)
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
end
