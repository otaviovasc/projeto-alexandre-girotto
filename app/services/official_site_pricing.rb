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

  BRAUNA_SERVICE_PRICES = {
    'cafe da manha' => 129.to_d,
    'almoco' => 109.to_d,
    'jantar' => 109.to_d,
    'piquenique' => 116.to_d
  }.freeze

  def quote(cabana:, start_date:, end_date:)
    raise Error, 'Cabana inválida para cálculo.' if cabana.blank?
    raise Error, 'Datas inválidas para cálculo.' if start_date.blank? || end_date.blank? || end_date <= start_date

    nights = each_night(start_date, end_date).map do |date|
      {
        date: date,
        price: price_for_night(cabana, date),
        weekend: weekend_night?(date),
        holiday: holiday_for_date(date).present?,
        season: season_for_date(date).fetch(:temporada)
      }
    end

    has_weekend = nights.any? { |night| night[:weekend] }
    has_holiday = nights.any? { |night| night[:holiday] }
    minimum = has_weekend || has_holiday ? 2 : 1
    stay_total = nights.sum { |night| night[:price] }
    nights_count = (end_date - start_date).to_i

    {
      nights: nights,
      nights_count: nights_count,
      stay_total: stay_total,
      minimum: minimum,
      meets_minimum: nights_count >= minimum,
      minimum_message: minimum_message(has_weekend: has_weekend, has_holiday: has_holiday, nights_count: nights_count)
    }
  end

  def service_price(service:, filial:)
    return nil if service.blank? || filial.blank?

    row = service_row_for(service.name)
    return nil if row.blank?
    return nil unless service_available_for_filial?(row, filial)

    brauna_price = BRAUNA_SERVICE_PRICES[normalize_service_name(row[:servico])]
    return brauna_price if brauna_filial?(filial) && brauna_price.present?

    row[:preco]
  end

  private

  def data
    Rails.cache.fetch("official_site_pricing:#{SHEET_ID}:v1", expires_in: CACHE_TTL) do
      {
        cabanas: rows_to_cabins(load_sheet('Cabanas')),
        precos: rows_to_prices(load_sheet('Precos')),
        feriados: rows_to_holidays(load_sheet('Feriados')),
        servicos: rows_to_services(load_sheet('Servicos'))
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

  def rows_to_services(rows)
    services = rows.map do |row|
      {
        categoria: row['Categoria'],
        servico: row['Servico'].to_s.strip,
        preco: sheet_number(row['Preco']),
        disponivel_serra: service_availability(row, 'Disponivel Serra'),
        disponivel_brauna: service_availability(row, 'Disponivel Brauna'),
        cobranca: row['Cobranca'],
        observacoes: row['Observacoes']
      }
    end

    apply_service_overrides(services)
  end

  def apply_service_overrides(services)
    adjusted = services.map do |service|
      normalize_service_name(service[:servico]) == 'tabua de frios' ? service.merge(preco: 167.to_d) : service
    end

    return adjusted if adjusted.any? { |service| normalize_service_name(service[:servico]).include?('bicic') }

    adjusted + [{
      categoria: 'Passeios e Relaxamento',
      servico: 'Bicicletas',
      preco: 80.to_d,
      disponivel_serra: false,
      disponivel_brauna: true,
      cobranca: 'por diaria',
      observacoes: 'Disponivel apenas na Fattoria di Brauna.'
    }]
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

  def service_row_for(service_name)
    target = normalize_service_name(service_name)
    services = data[:servicos]

    services.find { |service| normalize_service_name(service[:servico]) == target } ||
      services.find do |service|
        normalized = normalize_service_name(service[:servico])
        normalized.include?(target) || target.include?(normalized)
      end ||
      fuzzy_service_row(services, target)
  end

  def fuzzy_service_row(services, target)
    target_tokens = target.split
    return if target_tokens.blank?

    services
      .map do |service|
        normalized = normalize_service_name(service[:servico])
        score = (target_tokens & normalized.split).size
        [service, score]
      end
      .select { |_service, score| score >= 2 }
      .max_by { |_service, score| score }
      &.first
  end

  def service_available_for_filial?(service_row, filial)
    brauna_filial?(filial) ? service_row[:disponivel_brauna] : service_row[:disponivel_serra]
  end

  def brauna_filial?(filial)
    normalize_text(filial&.name || filial).include?('brauna')
  end

  def service_availability(row, key)
    serra = sheet_boolean(row['Disponivel Serra'], nil)
    brauna = sheet_boolean(row['Disponivel Brauna'], nil)
    return true if serra.nil? && brauna.nil?

    sheet_boolean(row[key], false)
  end

  def minimum_message(has_weekend:, has_holiday:, nights_count:)
    return '' if nights_count >= 2
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
    recurring_holiday_for_date(date) ||
      data[:feriados].find do |holiday|
        holiday[:ativo] != false &&
          holiday[:inicio].present? &&
          holiday[:fim].present? &&
          date >= holiday[:inicio] &&
          date <= holiday[:fim]
      end
  end

  def recurring_holiday_for_date(date)
    RECURRING_HOLIDAYS[date.strftime('%m-%d')]
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

  def normalize_service_name(value)
    normalize_text(value)
      .gsub(/\b(?:sp|mg)\b/, ' ')
      .squish
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
