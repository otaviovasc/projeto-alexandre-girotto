require 'bigdecimal'
require 'json'
require 'net/http'

class OfficialSitePricing
  class Error < StandardError; end

  SHEET_ID = ENV.fetch('OFFICIAL_PRICE_SHEET_ID', '1kx3L64fvkYdUMnGIK0zSh2UuBdIWObj-').freeze
  CACHE_TTL = 10.minutes

  MONTH_SEASONS = {
    1 => { temporada: 'Alta Temporada', multiplicador: 1.21.to_d },
    2 => { temporada: 'Media Temporada', multiplicador: 1.10.to_d },
    3 => { temporada: 'Baixa Temporada', multiplicador: 1.to_d },
    4 => { temporada: 'Baixa Temporada', multiplicador: 1.to_d },
    5 => { temporada: 'Alta Temporada', multiplicador: 1.21.to_d },
    6 => { temporada: 'Alta Temporada', multiplicador: 1.21.to_d },
    7 => { temporada: 'Alta Temporada', multiplicador: 1.21.to_d },
    8 => { temporada: 'Alta Temporada', multiplicador: 1.21.to_d },
    9 => { temporada: 'Media Temporada', multiplicador: 1.10.to_d },
    10 => { temporada: 'Media Temporada', multiplicador: 1.10.to_d },
    11 => { temporada: 'Media Temporada', multiplicador: 1.10.to_d },
    12 => { temporada: 'Alta Temporada', multiplicador: 1.21.to_d }
  }.freeze

  RECURRING_HOLIDAYS = {
    '01-01' => { nome: 'Ano Novo', acrescimo: 0.25.to_d },
    '12-31' => { nome: 'Virada do ano', acrescimo: 0.25.to_d }
  }.freeze

  def quote(cabana:, start_date:, end_date:)
    raise Error, 'Cabana inválida para cálculo.' if cabana.blank?
    raise Error, 'Datas inválidas para cálculo.' if start_date.blank? || end_date.blank? || end_date <= start_date

    nights = each_night(start_date, end_date).map do |date|
      holiday = holiday_for_date(date)

      {
        date: date,
        price: price_for_night(cabana, date),
        weekend: weekend_night?(date),
        holiday: holiday.present?,
        holiday_name: holiday&.fetch(:nome, nil),
        holiday_date: holiday&.fetch(:data_feriado, nil)&.to_s,
        season: season_for_date(date).fetch(:temporada)
      }
    end

    has_weekend = nights.any? { |night| night[:weekend] }
    has_holiday = nights.any? { |night| night[:holiday] }
    minimum = minimum_for_stay(cabana, start_date, end_date)
    stay_total = nights.sum { |night| night[:price] }
    nights_count = (end_date - start_date).to_i

    {
      nights: nights,
      nights_count: nights_count,
      stay_total: stay_total,
      minimum: minimum,
      meets_minimum: nights_count >= minimum,
      minimum_message: minimum_message(
        has_weekend: has_weekend,
        has_holiday: has_holiday,
        nights_count: nights_count,
        minimum: minimum
      )
    }
  end

  def available?(cabana:, start_date:, end_date:)
    cabin_available_for_range?(cabana, start_date, end_date)
  end

  private

  def data
    Rails.cache.fetch("official_site_pricing:#{SHEET_ID}:v1", expires_in: CACHE_TTL) do
      {
        cabanas: rows_to_cabins(load_sheet('Cabanas')),
        precos: rows_to_prices(load_sheet('Precos')),
        feriados: rows_to_holidays(load_sheet('Feriados'))
      }
    end
  rescue Error
    raise
  rescue => e
    raise Error, "Não foi possível carregar a planilha oficial de preços: #{e.message}"
  end

  def load_sheet(sheet)
    uri = URI("https://docs.google.com/spreadsheets/d/#{SHEET_ID}/gviz/tq")
    uri.query = URI.encode_www_form(tqx: 'out:json', sheet: sheet, _: Time.current.to_i)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) do |http|
      http.get(uri.request_uri)
    end

    raise Error, "A aba #{sheet} não respondeu corretamente." unless response.is_a?(Net::HTTPSuccess)

    gviz_rows(response.body, sheet)
  end

  def gviz_rows(body, sheet)
    start_index = body.index('{')
    end_index = body.rindex('}')
    raise Error, "A aba #{sheet} retornou dados inválidos." if start_index.blank? || end_index.blank?

    payload = JSON.parse(body[start_index..end_index])
    raise Error, "A aba #{sheet} retornou erro." unless payload['status'] == 'ok'

    table = payload.fetch('table')
    labels = Array(table['cols']).map { |column| column['label'].to_s.strip }
    rows = Array(table['rows']).map do |row|
      Array(row['c']).map { |cell| cell && (cell.key?('v') ? cell['v'] : cell['f']) }
    end

    headers = if labels.any?(&:present?)
                labels
              else
                rows.shift.to_a.map { |value| value.to_s.strip }
              end

    rows.filter_map do |row|
      record = headers.each_with_index.with_object({}) do |(header, index), result|
        next if header.blank?

        result[header] = row[index]
      end
      record if record.values.any?(&:present?)
    end
  rescue JSON::ParserError => e
    raise Error, "A aba #{sheet} retornou JSON inválido: #{e.message}"
  end

  def rows_to_cabins(rows)
    rows.map do |row|
      {
        cabana: normalize_cabin(row['Cabana']),
        filial: row['Filial'].to_s.strip,
        baixa_semana: sheet_number(row['Baixa semana']),
        baixa_fim_de_semana: sheet_number(row['Baixa fim de semana']),
        ativa: sheet_boolean(row['Ativa'], true)
      }
    end
  end

  def rows_to_prices(rows)
    rows.map do |row|
      {
        cabana: normalize_cabin(row['Cabana']),
        filial: row['Filial'].to_s.strip,
        baixa_semana: sheet_number(row['Baixa semana']),
        baixa_fds: sheet_number(row['Baixa fds']),
        media_semana: sheet_number(row['Media semana']),
        media_fds: sheet_number(row['Media fds']),
        alta_semana: sheet_number(row['Alta semana']),
        alta_fds: sheet_number(row['Alta fds']),
        feriado_baixa_semana: sheet_number(row['Feriado baixa semana']),
        feriado_baixa_fds: sheet_number(row['Feriado baixa fds']),
        feriado_media_semana: sheet_number(row['Feriado media semana']),
        feriado_media_fds: sheet_number(row['Feriado media fds']),
        feriado_alta_semana: sheet_number(row['Feriado alta semana']),
        feriado_alta_fds: sheet_number(row['Feriado alta fds'])
      }
    end
  end

  def rows_to_holidays(rows)
    rows.map do |row|
      {
        nome: row['Nome'],
        inicio: sheet_date(row['Inicio']),
        fim: sheet_date(row['Fim']),
        acrescimo: sheet_number(row['Acrescimo']),
        ativo: sheet_boolean(row['Ativo'], true),
        minimo_diarias: sheet_number(row['Minimo diarias']).to_i
      }
    end
  end

  def price_for_night(cabana, date)
    weekend = weekend_night?(date)
    season = season_for_date(date)
    holiday = holiday_for_date(date)
    price_row = price_row_for_cabana(cabana)

    if price_row.present?
      season_key = season_key_for_name(season[:temporada])
      day_key = weekend ? 'fds' : 'semana'
      holiday_key = "feriado_#{season_key}_#{day_key}".to_sym
      regular_key = "#{season_key}_#{day_key}".to_sym
      price = holiday.present? ? price_row[holiday_key].presence || price_row[regular_key] : price_row[regular_key]
      return price if price.to_d.positive?
    end

    fallback_cabin = cabin_row_for(cabana)
    base = weekend ? fallback_cabin&.fetch(:baixa_fim_de_semana, 0.to_d) : fallback_cabin&.fetch(:baixa_semana, 0.to_d)
    multiplier = season[:multiplicador] || 1.to_d
    holiday_addition = holiday.present? ? (holiday[:acrescimo].presence || 0.25.to_d) : 0.to_d

    (base.to_d * multiplier * (1.to_d + holiday_addition)).round
  end

  def price_row_for_cabana(cabana)
    target_cabana = normalize_cabin(cabana.name)
    target_filial = normalize_text(cabana.filial&.name)

    data[:precos].find do |row|
      normalize_cabin(row[:cabana]) == target_cabana &&
        normalize_text(row[:filial]) == target_filial
    end
  end

  def cabin_row_for(cabana)
    target_cabana = normalize_cabin(cabana.name)
    target_filial = normalize_text(cabana.filial&.name)

    data[:cabanas].find do |row|
      normalize_cabin(row[:cabana]) == target_cabana &&
        normalize_text(row[:filial]) == target_filial
    end
  end

  def minimum_for_stay(cabana, start_date, end_date)
    nights = each_night(start_date, end_date)
    requires_two = nights.any? { |date| base_minimum_for_night(date) > 1 }
    return 1 unless requires_two
    return 2 unless (end_date - start_date).to_i == 1

    allows_one_night_gap?(cabana, start_date, end_date) ? 1 : 2
  end

  def allows_one_night_gap?(cabana, start_date, end_date)
    return false unless (end_date - start_date).to_i == 1
    return false unless cabin_available_for_range?(cabana, start_date, end_date)

    if weekend_night?(start_date)
      allows_one_night_weekend_gap?(cabana, start_date, end_date)
    else
      allows_one_night_adjacent_gap?(cabana, start_date, end_date)
    end
  end

  def allows_one_night_weekend_gap?(cabana, start_date, end_date)
    if start_date.friday?
      !cabin_available_for_range?(cabana, end_date, end_date + 1.day)
    elsif start_date.saturday?
      !cabin_available_for_range?(cabana, start_date - 1.day, start_date)
    else
      false
    end
  end

  def allows_one_night_adjacent_gap?(cabana, start_date, end_date)
    previous_night_blocked = !cabin_available_for_range?(cabana, start_date - 1.day, start_date)
    next_night_blocked = !cabin_available_for_range?(cabana, end_date, end_date + 1.day)

    previous_night_blocked || next_night_blocked
  end

  def base_minimum_for_night(date)
    weekend_night?(date) || holiday_for_date(date).present? ? 2 : 1
  end

  def cabin_available_for_range?(cabana, start_date, end_date)
    return false if cabana.blank? || start_date.blank? || end_date.blank? || end_date <= start_date

    range = start_date...end_date

    active_availability_reservations(cabana).none? do |reserva|
      reserva_range = reserva.availability_range
      reserva_range.present? && reserva_range.overlaps?(range)
    end
  end

  def active_availability_reservations(cabana)
    Reserva.where(cabana_id: cabana.id)
           .where(blocks_availability: true)
           .where(payment_status: %w[pending waiting_payment paid])
           .where('payment_expires_at IS NULL OR payment_expires_at > ?', Time.current)
  end

  def minimum_message(has_weekend:, has_holiday:, nights_count:, minimum:)
    return '' if nights_count >= minimum
    return 'Feriados exigem mínimo de 2 diárias.' if has_holiday
    return 'Finais de semana exigem mínimo de 2 diárias.' if has_weekend

    ''
  end

  def each_night(start_date, end_date)
    nights = []
    date = start_date
    while date < end_date
      nights << date
      date += 1
    end
    nights
  end

  def weekend_night?(date)
    date.friday? || date.saturday?
  end

  def season_for_date(date)
    MONTH_SEASONS.fetch(date.month, { temporada: 'Baixa Temporada', multiplicador: 1.to_d })
  end

  def holiday_for_date(date)
    recurring_holiday_for_date(date) || configured_holiday_for_date(date)
  end

  def recurring_holiday_for_date(date)
    night_date = date.to_date
    years = [night_date.year - 1, night_date.year, night_date.year + 1]

    years.each do |year|
      RECURRING_HOLIDAYS.each do |key, holiday|
        month, day = key.split('-').map(&:to_i)
        holiday_date = Date.new(year, month, day)

        if holiday_pricing_window_cover?(night_date, holiday_date)
          return holiday.merge(
            inicio: holiday_date,
            fim: holiday_date,
            data_feriado: holiday_date
          )
        end
      end
    end

    nil
  end

  def configured_holiday_for_date(date)
    night_date = date.to_date

    data[:feriados].each do |holiday|
      next if holiday[:ativo] == false
      next if holiday[:inicio].blank? || holiday[:fim].blank?

      (holiday[:inicio]..holiday[:fim]).each do |holiday_date|
        return holiday.merge(data_feriado: holiday_date) if holiday_pricing_window_cover?(night_date, holiday_date)
      end
    end

    nil
  end

  def holiday_pricing_window_cover?(night_date, holiday_date)
    window = holiday_pricing_window(holiday_date)
    night_date >= window[:start] && night_date <= window[:end]
  end

  def holiday_pricing_window(holiday_date)
    case holiday_date.wday
    when 2
      { start: holiday_date - 4.days, end: holiday_date }
    when 4
      { start: holiday_date, end: holiday_date + 2.days }
    else
      { start: holiday_date, end: holiday_date }
    end
  end

  def season_key_for_name(name)
    normalized = normalize_text(name)
    return 'alta' if normalized.include?('alta')
    return 'media' if normalized.include?('media')

    'baixa'
  end

  def normalize_cabin(value)
    name = value.to_s.split(' - ').first.strip
    return 'Villa Vita' if name == 'Vita'
    return 'Vecchio Toro' if name == 'Vecchio'

    name
  end

  def normalize_text(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, ' ')
        .squish
  end

  def sheet_number(value)
    return value.to_d if value.is_a?(Numeric)

    text = value.to_s.gsub(/[^\d,.-]/, '').strip
    return 0.to_d if text.blank?

    normalized = text.include?(',') ? text.delete('.').tr(',', '.') : text
    BigDecimal(normalized)
  rescue ArgumentError
    0.to_d
  end

  def sheet_boolean(value, fallback = false)
    return value if value == true || value == false
    return fallback if value.blank?

    normalized = normalize_text(value)
    return true if %w[true sim s yes y 1].include?(normalized)
    return false if %w[false nao n no 0].include?(normalized)

    fallback
  end

  def sheet_date(value)
    return value.to_date if value.respond_to?(:to_date)

    text = value.to_s
    if (match = text.match(/\ADate\((\d+),(\d+),(\d+)\)/))
      year, month, day = match.captures.map(&:to_i)
      return Date.new(year, month + 1, day)
    end

    Date.parse(text)
  rescue ArgumentError, TypeError
    nil
  end
end
