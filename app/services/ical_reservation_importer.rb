require 'digest'
require 'icalendar'
require 'open-uri'

class IcalReservationImporter
  LOOKAHEAD = 11.months
  SELF_ORIGIN_MARKERS = [
    'conforme site oficial',
    'villaggio girotto',
    'village girotto',
    'meusistema.com',
    'meu sistema de reservas',
    'reserva importada do sistema',
    'sistema oficial villaggio'
  ].freeze
  EXTERNAL_CALENDAR_BLOCK_MARKERS = [
    'blocked by external calendar',
    'bloqueado por calendario externo',
    'bloqueado por calendário externo',
    'imported calendar',
    'calendario importado',
    'calendário importado'
  ].freeze

  EventRange = Struct.new(:uid, :uid_from_feed, :platform_uid, :start_date, :end_date, keyword_init: true)
  Result = Struct.new(:created, :updated, :skipped, :missing, keyword_init: true) do
    def imported_count
      created + updated
    end
  end

  def initialize(cabana:, platform:, url:, ics_content: nil, today: Date.current, lookahead: LOOKAHEAD)
    @cabana = cabana
    @platform = platform.to_s.strip.downcase.presence || 'ical'
    @url = url
    @ics_content = ics_content
    @today = today
    @lookahead = lookahead
  end

  def call
    result = Result.new(created: 0, updated: 0, skipped: 0, missing: 0)
    user = imported_user
    imported_ids = []

    event_ranges = normalized_ranges
    matched_reservas = event_ranges.to_h do |event_range|
      [event_range.object_id, find_existing_import(event_range)]
    end
    infer_booking_date_changes(event_ranges, matched_reservas)

    event_ranges.each do |event_range|
      reserva = matched_reservas[event_range.object_id]

      if reserva
        imported_ids << reserva.id

        if preserve_manual_override?(reserva, event_range)
          update_import_metadata(reserva, event_range)
          ensure_cleaning_services(reserva)
          result.skipped += 1
        elsif reserva.start_date == event_range.start_date && reserva.end_date == event_range.end_date
          update_import_metadata(reserva, event_range)
          ensure_cleaning_services(reserva)
          result.skipped += 1
        else
          apply_imported_date_change(reserva, event_range)
          ensure_cleaning_services(reserva, force_dates: true)
          sync_breakfast_service_date(reserva)
          result.updated += 1
        end
      else
        reserva = Reserva.create!(import_attributes(event_range).merge(
          start_date: event_range.start_date,
          end_date: event_range.end_date,
          user: user,
          cabana: @cabana,
          origem: @platform,
          payment_status: 'paid',
          total_price: 0.0,
          observation: "Importado via #{@platform.capitalize} - #{@cabana.name}"
        ))
        ensure_cleaning_services(reserva)
        ensure_breakfast_service(reserva)
        imported_ids << reserva.id
        result.created += 1
      end
    end

    result.missing = mark_missing_imports(imported_ids, event_ranges)

    result
  end

  private

  def normalized_ranges
    ranges = calendars.flat_map(&:events).filter_map { |event| range_for(event) }
    ranges.sort_by { |event_range| [event_range.start_date, event_range.end_date, event_range.uid] }
  end

  def calendars
    Icalendar::Calendar.parse(ics_content)
  end

  def ics_content
    @ics_content || URI.parse(@url).open.read
  end

  def range_for(event)
    return unless importable_event?(event)

    start_date = calendar_date(event.dtstart)
    return unless start_date

    end_date = calendar_date(event.dtend) || start_date + 1.day
    end_date = start_date + 1.day if end_date <= start_date

    return if end_date <= @today
    return if start_date > @today + @lookahead

    EventRange.new(
      uid: uid_for(event, start_date, end_date),
      uid_from_feed: event.uid.to_s.strip.present?,
      platform_uid: platform_uid_for(event),
      start_date: start_date,
      end_date: end_date
    )
  end

  def importable_event?(event)
    normalized_text = normalized_event_text(event)
    return false if airbnb_not_available_event?(normalized_text)
    return false if SELF_ORIGIN_MARKERS.any? { |marker| normalized_text.include?(marker) }
    return false if EXTERNAL_CALENDAR_BLOCK_MARKERS.any? { |marker| normalized_text.include?(marker) }

    true
  end

  def airbnb_not_available_event?(normalized_text)
    @platform == 'airbnb' && normalized_text.include?('not available')
  end

  def normalized_event_text(event)
    I18n.transliterate(raw_event_text(event)).downcase.squish
  end

  def raw_event_text(event)
    [
      event.uid,
      event.summary,
      event.description,
      event.location,
      event.organizer,
      event.categories
    ].compact.map(&:to_s).join(' ')
  end

  def calendar_date(value)
    return unless value

    raw_value = value.respond_to?(:value) ? value.value : value
    return raw_value if raw_value.is_a?(Date) && !raw_value.is_a?(DateTime)

    if raw_value.respond_to?(:in_time_zone)
      raw_value.in_time_zone.to_date
    elsif raw_value.respond_to?(:to_time)
      raw_value.to_time.in_time_zone.to_date
    elsif raw_value.respond_to?(:to_date)
      raw_value.to_date
    end
  end

  def uid_for(event, start_date, end_date)
    uid = event.uid.to_s.strip
    uid.presence || Digest::SHA1.hexdigest([@platform, start_date, end_date, event.summary].join(':'))
  end

  def platform_uid_for(event)
    extracted_platform_uid(raw_event_text(event)).presence || event.uid.to_s.strip.presence
  end

  def extracted_platform_uid(text)
    patterns = [
      %r{/reservations/details/([A-Z0-9_-]+)}i,
      /(?:res_id|reservation_id|booking_id|bookingid)\s*[=:]\s*([A-Z0-9_-]{4,})/i,
      /(?:codigo|código|numero|número)\s+(?:da|de)\s+(?:reserva|booking)\s*[:#-]?\s*([A-Z0-9][A-Z0-9_-]{4,})/i,
      /(?:reservation|reserva|booking)\s+(?:id|number|numero|número|code|codigo|código)\s*[:#-]?\s*([A-Z0-9][A-Z0-9_-]{4,})/i
    ]

    patterns.each do |pattern|
      match = text.match(pattern)
      return match[1].to_s.strip.upcase if match
    end

    nil
  end

  def find_existing_import(event_range)
    if event_range.platform_uid.present?
      by_platform_uid = imported_reservas
                        .where.not(platform_uid: [nil, ''])
                        .find_by(platform_uid: event_range.platform_uid)
      return by_platform_uid if by_platform_uid
    end

    by_uid = imported_reservas.find_by(ical_uid: event_range.uid)
    return by_uid if by_uid

    by_imported_dates = imported_reservas
                        .where(imported_start_date: event_range.start_date, imported_end_date: event_range.end_date)
                        .order(Arel.sql('CASE WHEN ical_missing_since IS NULL THEN 0 ELSE 1 END'), :created_at)
                        .first
    return by_imported_dates if by_imported_dates

    by_current_dates = imported_reservas
                       .where(start_date: event_range.start_date, end_date: event_range.end_date)
                       .order(Arel.sql('CASE WHEN ical_missing_since IS NULL THEN 0 ELSE 1 END'), :created_at)
                       .first
    return by_current_dates if by_current_dates

    imported_reservas
      .where(ical_uid: [nil, ''])
      .where('start_date < ? AND end_date > ?', event_range.end_date, event_range.start_date)
      .order(:start_date)
      .first
  end

  def infer_booking_date_changes(event_ranges, matched_reservas)
    return unless @platform == 'booking'

    unmatched_ranges = event_ranges.select { |event_range| matched_reservas[event_range.object_id].nil? }
    return if unmatched_ranges.empty?

    matched_ids = matched_reservas.values.compact.map(&:id)
    candidates_scope = missing_import_scope.where(ical_missing_since: nil)
    candidates_scope = candidates_scope.where.not(id: matched_ids) if matched_ids.any?
    candidates = candidates_scope.to_a
    return if candidates.empty?

    inferred_date_change_pairs(unmatched_ranges, candidates).each do |event_range, reserva|
      matched_reservas[event_range.object_id] = reserva
      Rails.logger.info(
        "Possivel troca de datas Booking: reserva ##{reserva.id} " \
        "#{reserva.start_date} -> #{reserva.end_date} para " \
        "#{event_range.start_date} -> #{event_range.end_date}"
      )
    end
  end

  def inferred_date_change_pairs(unmatched_ranges, candidates)
    return [[unmatched_ranges.first, candidates.first]] if unmatched_ranges.one? && candidates.one?

    ranges_by_duration = unmatched_ranges.group_by { |event_range| event_duration(event_range) }
    candidates_by_duration = candidates.group_by { |reserva| reservation_source_duration(reserva) }

    ranges_by_duration.filter_map do |duration, ranges|
      duration_candidates = candidates_by_duration[duration] || []
      next unless ranges.one? && duration_candidates.one?

      [ranges.first, duration_candidates.first]
    end
  end

  def event_duration(event_range)
    (event_range.end_date - event_range.start_date).to_i
  end

  def reservation_source_duration(reserva)
    source_start = reserva.imported_start_date || reserva.start_date
    source_end = reserva.imported_end_date || reserva.end_date
    (source_end - source_start).to_i
  end

  def imported_reservas
    Reserva.where(cabana_id: @cabana.id)
           .where('LOWER(origem) = ?', @platform)
  end

  def preserve_manual_override?(reserva, event_range)
    return false unless reserva.manual_override?
    return false unless reserva.imported_start_date.present? && reserva.imported_end_date.present?

    reserva.imported_start_date == event_range.start_date &&
      reserva.imported_end_date == event_range.end_date
  end

  def import_attributes(event_range)
    {
      ical_uid: event_range.uid,
      platform_uid: event_range.platform_uid,
      ical_uid_from_feed: event_range.uid_from_feed,
      imported_start_date: event_range.start_date,
      imported_end_date: event_range.end_date,
      manual_override: false,
      ical_missing_since: nil
    }
  end

  def update_import_metadata(reserva, event_range)
    reserva.update_columns(
      ical_uid: event_range.uid,
      platform_uid: event_range.platform_uid,
      ical_uid_from_feed: event_range.uid_from_feed,
      imported_start_date: event_range.start_date,
      imported_end_date: event_range.end_date,
      ical_missing_since: nil
    )
  end

  def apply_imported_date_change(reserva, event_range)
    detected_at = Time.current
    previous_uid = reserva.platform_uid.presence || reserva.ical_uid
    previous_start_date = reserva.start_date
    previous_end_date = reserva.end_date

    Reserva.transaction do
      reserva.update!(import_attributes(event_range).merge(
        start_date: event_range.start_date,
        end_date: event_range.end_date,
        group_created: false,
        ical_date_change_since: detected_at
      ))

      reserva.ical_reservation_changes.create!(
        platform: @platform,
        old_uid: previous_uid,
        new_uid: event_range.platform_uid.presence || event_range.uid,
        old_start_date: previous_start_date,
        old_end_date: previous_end_date,
        new_start_date: event_range.start_date,
        new_end_date: event_range.end_date,
        created_at: detected_at,
        updated_at: detected_at
      )
    end
  end

  def ensure_cleaning_services(reserva, force_dates: false)
    CleaningServicesAssigner.new(reserva, force_dates: force_dates).call
  end

  def ensure_breakfast_service(reserva)
    BreakfastServicesAssigner.new(reserva, source: @platform).add_if_configured
  end

  def sync_breakfast_service_date(reserva)
    BreakfastServicesAssigner.new(reserva, source: @platform).sync_automatic_service_dates
  end

  def mark_missing_imports(imported_ids, event_ranges)
    missing_scope = missing_import_scope

    missing_scope = missing_scope.where.not(id: imported_ids) if imported_ids.any?

    current_platform_uids = event_ranges.map(&:platform_uid).compact_blank.uniq
    if current_platform_uids.any?
      date_change_scope = missing_scope.where(platform_uid: current_platform_uids)
      date_change_ids = date_change_scope.pluck(:id)

      if date_change_ids.any?
        date_change_scope.update_all(
          ical_missing_since: nil,
          ical_date_change_since: Time.current,
          group_created: false,
          updated_at: Time.current
        )
        missing_scope = missing_scope.where.not(id: date_change_ids)
      end
    end

    missing_scope.where(ical_missing_since: nil).update_all(ical_missing_since: Time.current)
    missing_scope.count
  end

  def missing_import_scope
    Reserva.where(cabana_id: @cabana.id)
           .where('LOWER(origem) = ?', @platform)
           .where(blocks_availability: true)
           .where(payment_status: %w[pending waiting_payment paid])
           .where('end_date > ?', @today)
           .where('start_date <= ?', @today + @lookahead)
           .where(
             "(ical_uid_from_feed = ? AND ical_uid IS NOT NULL AND ical_uid != '') OR " \
             "(platform_uid IS NOT NULL AND platform_uid != '')",
             true
           )
  end

  def imported_user
    User.find_or_create_by!(email: "#{platform_slug}@importado.com") do |user|
      user.name = @platform.capitalize
      user.telephone = "importado-#{Digest::SHA1.hexdigest(@platform).first(12)}"
      user.password = 'password'
      user.password_confirmation = 'password'
    end
  end

  def platform_slug
    @platform.parameterize(separator: '_').presence || 'ical'
  end
end
