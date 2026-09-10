# frozen_string_literal: true

class RecurringMaintenanceSync
  KIND = 'recurring_maintenance'
  EVENT_TYPE = 'maintenance'
  LOOKAHEAD_DAYS = 180

  Result = Struct.new(:checked_rules, :created, :reactivated, :updated, :cancelled, :kept, keyword_init: true) do
    def changed?
      created.to_i.positive? || reactivated.to_i.positive? || updated.to_i.positive? || cancelled.to_i.positive?
    end
  end

  def self.run(start_date: Date.current, end_date: Date.current + LOOKAHEAD_DAYS.days)
    new(start_date: start_date, end_date: end_date).call
  end

  def initialize(start_date:, end_date:)
    @start_date = start_date.to_date
    @end_date = end_date.to_date
    @result = Result.new(checked_rules: 0, created: 0, reactivated: 0, updated: 0, cancelled: 0, kept: 0)
  end

  def call
    return @result unless available?

    desired = desired_occurrences
    persist_desired_occurrences(desired)
    cancel_obsolete_occurrences(desired.keys)

    @result
  end

  private

  attr_reader :start_date, :end_date

  def available?
    defined?(RecurringMaintenanceRule) &&
      defined?(OperationalServiceOccurrence) &&
      RecurringMaintenanceRule.connection.data_source_exists?(RecurringMaintenanceRule.table_name) &&
      OperationalServiceOccurrence.connection.data_source_exists?(OperationalServiceOccurrence.table_name)
  end

  def desired_occurrences
    desired = {}

    RecurringMaintenanceRule.active.find_each do |rule|
      @result.checked_rules += 1

      rule.selected_cabanas.find_each do |cabana|
        rule.next_occurrence_dates(from: start_date, through: end_date).each do |service_date|
          stable_id = stable_id_for(rule, cabana, service_date)
          desired[stable_id] = {
            cabana: cabana,
            filial: cabana.filial,
            kind: KIND,
            event_type: EVENT_TYPE,
            name: rule.title,
            service_date: service_date,
            status: 'active',
            cancelled_at: nil,
            cancellation_reason: nil
          }
        end
      end
    end

    desired
  end

  def persist_desired_occurrences(desired)
    desired.each do |stable_id, attributes|
      occurrence = OperationalServiceOccurrence.find_or_initialize_by(stable_id: stable_id)
      was_new = occurrence.new_record?
      was_cancelled = occurrence.persisted? && occurrence.cancelled?

      occurrence.assign_attributes(attributes)

      if occurrence.changed?
        occurrence.save!
        if was_new
          @result.created += 1
        elsif was_cancelled
          @result.reactivated += 1
        else
          @result.updated += 1
        end
      else
        @result.kept += 1
      end
    end
  end

  def cancel_obsolete_occurrences(desired_stable_ids)
    OperationalServiceOccurrence
      .recurring_maintenance
      .active
      .where(service_date: start_date..end_date)
      .where.not(stable_id: desired_stable_ids)
      .find_each do |occurrence|
        occurrence.cancel!(reason: 'Manutenção recorrente removida, pausada ou alterada.')
        @result.cancelled += 1
      end
  end

  def stable_id_for(rule, cabana, service_date)
    "recurring-maintenance-rule-#{rule.id}-cabana-#{cabana.id}-#{service_date.iso8601}"
  end
end
