# frozen_string_literal: true

class RecurringMaintenanceWhatsappTaskSync
  TRIGGER_KEY_PREFIX = 'recurring_maintenance'
  TASK_HOUR = 9
  TASK_MINUTE = 0
  LOOKAHEAD_DAYS = 180

  Result = Struct.new(:checked_occurrences, :created, :updated, :removed, keyword_init: true)

  def self.run(date: Date.current, through: Date.current + LOOKAHEAD_DAYS.days)
    new(date: date, through: through).run
  end

  def initialize(date:, through:)
    @date = date.to_date
    @through = through.to_date
    @result = Result.new(checked_occurrences: 0, created: 0, updated: 0, removed: 0)
  end

  def run
    return @result unless available?

    desired_task_keys = []

    grouped_occurrences.each_value do |group|
      occurrence = group[:occurrences].first
      desired_task_keys << task_key_for(occurrence, group[:trigger_key], group[:recipient])
      upsert_task(occurrence, group[:rule], group[:recipient], group[:occurrences], group[:trigger_key])
    end

    remove_obsolete_tasks(desired_task_keys)

    @result
  end

  private

  attr_reader :date, :through

  def available?
    defined?(RecurringMaintenanceRule) &&
      defined?(OperationalServiceOccurrence) &&
      defined?(ReservationWhatsappTask) &&
      RecurringMaintenanceRule.connection.data_source_exists?(RecurringMaintenanceRule.table_name) &&
      OperationalServiceOccurrence.connection.data_source_exists?(OperationalServiceOccurrence.table_name) &&
      ReservationWhatsappTask.connection.data_source_exists?(ReservationWhatsappTask.table_name)
  end

  def occurrences_scope
    OperationalServiceOccurrence
      .recurring_maintenance
      .where(service_date: date..through)
      .includes(cabana: :filial)
  end

  def grouped_occurrences
    groups = {}

    occurrences_scope.find_each do |occurrence|
      @result.checked_occurrences += 1
      next if occurrence.cancelled?

      rule = rule_for(occurrence)
      next if rule.blank? || !rule.active?

      rule.recipients.each do |recipient|
        next if recipient[:phone].blank?

        trigger_key = trigger_key_for(rule, occurrence, recipient)
        group_key = [rule.id, occurrence.filial_id, occurrence.service_date, recipient[:phone]]
        groups[group_key] ||= {
          rule: rule,
          recipient: recipient,
          trigger_key: trigger_key,
          occurrences: []
        }
        groups[group_key][:occurrences] << occurrence
      end
    end

    groups.each_value do |group|
      group[:occurrences].sort_by! { |occurrence| [occurrence.cabana&.name.to_s, occurrence.id] }
    end

    groups
  end

  def upsert_task(occurrence, rule, recipient, occurrences, trigger_key)
    task = ReservationWhatsappTask.find_or_initialize_by(
      operational_service_occurrence: occurrence,
      trigger_key: trigger_key,
      recipient_phone: recipient[:phone]
    )

    scheduled_at = scheduled_at_for(occurrence)
    message_body = render_message(rule.message_body, occurrence, recipient, occurrences)
    template_name = task_name_for(rule, occurrence)

    content_changed = task.persisted? && (
      task.template_name != template_name ||
      task.message_body != message_body ||
      task.scheduled_at != scheduled_at ||
      task.scheduled_on != scheduled_at.to_date ||
      task.recipient_name != recipient[:name] ||
      task.recipient_phone != recipient[:phone]
    )

    task.assign_attributes(
      reserva: nil,
      reservation_email_template: nil,
      template_name: template_name,
      message_body: message_body,
      scheduled_at: scheduled_at,
      scheduled_on: scheduled_at.to_date,
      recipient_name: recipient[:name],
      recipient_phone: recipient[:phone]
    )

    if content_changed
      task.completed_at = nil
      task.morning_notified_on = nil
      task.evening_notified_on = nil
    end

    return unless task.changed?

    task.new_record? ? @result.created += 1 : @result.updated += 1
    task.save!
  end

  def remove_obsolete_tasks(desired_task_keys)
    scope = ReservationWhatsappTask
            .pending
            .where("trigger_key LIKE ?", "#{TRIGGER_KEY_PREFIX}:%")
            .where(scheduled_on: (date - 1.day)..through)
            .includes(:operational_service_occurrence)

    scope.find_each do |task|
      next if desired_task_keys.include?([task.operational_service_occurrence_id, task.trigger_key, task.recipient_phone])

      task.destroy!
      @result.removed += 1
    end
  end

  def rule_for(occurrence)
    rule_id = occurrence.stable_id.to_s[/recurring-maintenance-rule-(\d+)-/, 1]
    return if rule_id.blank?

    RecurringMaintenanceRule.find_by(id: rule_id)
  end

  def scheduled_at_for(occurrence)
    scheduled_date = occurrence.service_date - 1.day
    Time.zone.local(scheduled_date.year, scheduled_date.month, scheduled_date.day, TASK_HOUR, TASK_MINUTE)
  end

  def task_name_for(rule, occurrence)
    filial_name = occurrence.filial&.name.to_s
    suffix = filial_name.present? ? " - #{filial_name}" : ''
    "Manutenção: #{rule.title}#{suffix}"
  end

  def task_key_for(occurrence, trigger_key, recipient)
    [occurrence.id, trigger_key, recipient[:phone]]
  end

  def trigger_key_for(rule, occurrence, recipient)
    [
      TRIGGER_KEY_PREFIX,
      "rule-#{rule.id}",
      "filial-#{occurrence.filial_id}",
      occurrence.service_date.iso8601,
      recipient[:phone]
    ].join(':')
  end

  def render_message(template, occurrence, recipient, occurrences)
    filial = occurrence.filial || occurrence.cabana&.filial
    cabanas = occurrences.map { |item| cabana_label(item.cabana) }.reject(&:blank?).uniq
    cabanas_text = cabanas.join(', ')
    cabanas_list = cabanas.map { |name| "- #{name}" }.join("\n")

    replacements = {
      'titulo' => occurrence.name,
      'cabana' => cabanas_text,
      'cabanas' => cabanas_text,
      'cabanas_lista' => cabanas_list,
      'filial' => filial&.name.to_s,
      'data' => occurrence.service_date.strftime('%d/%m/%Y'),
      'data_curta' => occurrence.service_date.strftime('%d/%m'),
      'nome' => recipient[:name].to_s,
      'telefone' => recipient[:phone].to_s
    }

    replacements.reduce(template.to_s) do |message, (key, value)|
      message.gsub("{{#{key}}}", value)
    end
  end

  def cabana_label(cabana)
    cabana&.guest_display_name.presence || cabana&.name.to_s
  end
end
