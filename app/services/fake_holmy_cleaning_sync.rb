# frozen_string_literal: true

require 'set'

class FakeHolmyCleaningSync
  KIND = 'fake_holmy_cleaning'
  ENTRY_NAME = 'Limpeza Entrada (Holmy)'
  EXIT_NAME = 'Limpeza Saida (Holmy)'
  ENTRY_TYPE = 'entry'
  EXIT_TYPE = 'exit'
  LOOKAHEAD_DAYS = 180

  Result = Struct.new(:checked_cabanas, :created, :reactivated, :updated, :cancelled, :kept, keyword_init: true) do
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
    @result = Result.new(checked_cabanas: 0, created: 0, reactivated: 0, updated: 0, cancelled: 0, kept: 0)
  end

  def call
    return @result unless available?

    target_cabanas.each do |cabana|
      sync_cabana(cabana)
      @result.checked_cabanas += 1
    end

    @result
  end

  private

  attr_reader :start_date, :end_date

  def available?
    defined?(OperationalServiceOccurrence) &&
      OperationalServiceOccurrence.connection.data_source_exists?(OperationalServiceOccurrence.table_name)
  end

  def target_cabanas
    Cabana.includes(:filial).reject { |cabana| excluded_cabana?(cabana) }
  end

  def excluded_cabana?(cabana)
    cabana_name = normalize(cabana.name)
    filial_name = normalize(cabana.filial&.name)

    cabana_name.include?('vita') && filial_name.include?('serra da mantiqueira')
  end

  def sync_cabana(cabana)
    window_start = start_date
    window_end = end_date + 2.days
    occupied_dates = occupied_dates_for(cabana, window_start, window_end)
    real_cleaning_dates = real_cleaning_dates_for(cabana, window_start, window_end)
    desired = desired_occurrences_for(cabana, window_start, window_end, occupied_dates, real_cleaning_dates)

    persist_desired_occurrences(cabana, desired)
    cancel_obsolete_occurrences(cabana, desired.keys, start_date, end_date)
  end

  def occupied_dates_for(cabana, window_start, window_end)
    dates = Set.new

    Reserva
      .where(cabana_id: cabana.id, payment_status: 'paid', blocks_availability: true)
      .where('start_date < ? AND end_date > ?', window_end + 1.day, window_start)
      .find_each do |reserva|
        (reserva.start_date...reserva.end_date).each do |date|
          dates << date if date.between?(window_start, window_end)
        end
      end

    dates
  end

  def real_cleaning_dates_for(cabana, window_start, window_end)
    ReservaService
      .joins(:service, reserva: :cabana)
      .where(reservas: { cabana_id: cabana.id })
      .where(status: 'active')
      .where(service_date: window_start..window_end)
      .select { |reserva_service| CleaningServicesAssigner.cleaning_service?(reserva_service.service) }
      .map(&:service_date)
      .compact
      .to_set
  end

  def desired_occurrences_for(cabana, window_start, window_end, occupied_dates, real_cleaning_dates)
    desired = {}
    empty_streak = []
    date = window_start

    while date <= window_end
      if empty_day?(date, occupied_dates, real_cleaning_dates)
        empty_streak << date

        if empty_streak.size >= 5
          entry_date = empty_streak[4]
          exit_date = entry_date + 2.days
          planned_pair = planned_pair(entry_date, exit_date, occupied_dates, real_cleaning_dates)

          if planned_pair && pair_inside_export_window?(planned_pair)
            add_pair_to_desired(desired, cabana, planned_pair.first, planned_pair.last)
            date = planned_pair.last + 1.day
            empty_streak = []
            next
          end
        end
      else
        empty_streak = []
      end

      date += 1.day
    end

    desired
  end

  def pair_inside_export_window?(planned_pair)
    planned_pair.first.between?(start_date, end_date) && planned_pair.last.between?(start_date, end_date)
  end

  def planned_pair(entry_date, exit_date, occupied_dates, real_cleaning_dates)
    next_real_cleaning_date = real_cleaning_dates.select { |date| date >= entry_date }.min

    if next_real_cleaning_date && exit_date >= next_real_cleaning_date
      shifted_entry_date = entry_date - 1.day
      shifted_exit_date = exit_date - 1.day

      return [shifted_entry_date, shifted_exit_date] if shifted_exit_date < next_real_cleaning_date &&
                                                        empty_range?(shifted_entry_date, shifted_exit_date, occupied_dates, real_cleaning_dates)

      return nil
    end

    return [entry_date, exit_date] if empty_range?(entry_date, exit_date, occupied_dates, real_cleaning_dates)

    nil
  end

  def add_pair_to_desired(desired, cabana, entry_date, exit_date)
    [
      [ENTRY_TYPE, ENTRY_NAME, entry_date],
      [EXIT_TYPE, EXIT_NAME, exit_date]
    ].each do |event_type, name, service_date|
      stable_id = stable_id_for(cabana, event_type, service_date)
      desired[stable_id] = {
        cabana: cabana,
        filial: cabana.filial,
        kind: KIND,
        event_type: event_type,
        name: name,
        service_date: service_date,
        status: 'active',
        cancelled_at: nil,
        cancellation_reason: nil
      }
    end
  end

  def persist_desired_occurrences(_cabana, desired)
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

  def cancel_obsolete_occurrences(cabana, desired_stable_ids, window_start, window_end)
    OperationalServiceOccurrence
      .fake_holmy_cleaning
      .active
      .where(cabana_id: cabana.id, service_date: window_start..window_end)
      .where.not(stable_id: desired_stable_ids)
      .find_each do |occurrence|
        occurrence.cancel!(reason: 'Limpeza Holmy automatica invalidada por reserva ou limpeza real.')
        @result.cancelled += 1
      end
  end

  def empty_range?(entry_date, exit_date, occupied_dates, real_cleaning_dates)
    (entry_date..exit_date).all? { |date| empty_day?(date, occupied_dates, real_cleaning_dates) }
  end

  def empty_day?(date, occupied_dates, real_cleaning_dates)
    !occupied_dates.include?(date) && !real_cleaning_dates.include?(date)
  end

  def stable_id_for(cabana, event_type, service_date)
    "fake-holmy-cabana-#{cabana.id}-#{service_date.iso8601}-#{event_type}"
  end

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.squish
  end
end
