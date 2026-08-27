class OfficialQuoteApi
  include ActiveSupport::NumberHelper

  class Error < StandardError; end

  def initialize(destino:, checkin:, checkout:, cabana: nil, details: false, pricing: OfficialSitePricing.new)
    @destino_param = destino
    @checkin = parse_date(checkin)
    @checkout = parse_date(checkout)
    @cabana_param = cabana
    @details = ActiveModel::Type::Boolean.new.cast(details)
    @pricing = pricing
  end

  def call
    validate!

    cabins = matching_cabins
    raise Error, 'Nenhuma cabana encontrada para esse destino.' if cabins.blank?

    rows = cabins.map { |cabana| quote_for_cabana(cabana) }
                .sort_by { |row| [row[:disponivel] ? 0 : 1, row[:nome]] }

    {
      ok: true,
      generated_at: Time.current.iso8601,
      fontes: {
        precos: 'Google Sheets',
        disponibilidade: 'Render'
      },
      destino: destination_name,
      checkin: @checkin.to_s,
      checkout: @checkout.to_s,
      noites: nights_count,
      cabanas: rows
    }
  end

  private

  def validate!
    raise Error, 'Informe o destino.' if @destino_param.blank?
    raise Error, 'Informe check-in e check-out em formato válido.' if @checkin.blank? || @checkout.blank?
    raise Error, 'O check-out precisa ser depois do check-in.' if @checkout <= @checkin
    raise Error, 'O check-in não pode estar no passado.' if @checkin < Date.current
  end

  def quote_for_cabana(cabana)
    quote = @pricing.quote(cabana: cabana, start_date: @checkin, end_date: @checkout)
    available = @pricing.available?(cabana: cabana, start_date: @checkin, end_date: @checkout)
    bookable = available && quote[:meets_minimum]
    reasons = unavailable_reasons(available: available, quote: quote)

    payload = {
      id: cabana.id,
      nome: cabana.name,
      destino: cabana.filial&.name.to_s,
      disponivel: bookable,
      status: bookable ? 'disponivel' : 'indisponivel',
      motivos: reasons,
      hospedagem: quote[:stay_total].to_f,
      hospedagem_formatada: money(quote[:stay_total]),
      minimo_diarias: quote[:minimum],
      minimo_diarias_ok: quote[:meets_minimum]
    }

    payload[:diarias] = daily_payload(quote) if @details
    payload
  end

  def unavailable_reasons(available:, quote:)
    reasons = []
    reasons << 'Cabana ocupada nesse período.' unless available
    reasons << quote[:minimum_message] unless quote[:meets_minimum]
    reasons
  end

  def daily_payload(quote)
    quote[:nights].map do |night|
      {
        data: night[:date].to_s,
        valor: night[:price].to_f,
        valor_formatado: money(night[:price]),
        tipo: night[:weekend] ? 'fim_de_semana' : 'semana',
        temporada: night[:season],
        feriado: night[:holiday],
        nome_feriado: night[:holiday_name],
        data_feriado: night[:holiday_date]
      }
    end
  end

  def matching_cabins
    cabins = Cabana.joins(:filial)
                   .includes(:filial)
                   .where(filials: { name: destination_name })
                   .order(:name)
                   .to_a

    return cabins if @cabana_param.blank?

    target = normalize_text(@cabana_param)
    cabins.select do |cabana|
      normalized = normalize_text(cabana.name)
      normalized == target || normalized.include?(target) || target.include?(normalized)
    end
  end

  def destination_name
    @destination_name ||= begin
      normalized = normalize_text(@destino_param)

      if normalized.include?('brauna') || normalized.include?('fattoria')
        'Fattoria di Brauna'
      elsif normalized.include?('serra') || normalized.include?('mantiqueira') ||
            normalized.include?('marmelopolis') || normalized.include?('minas')
        'Serra da Mantiqueira'
      else
        filial = Filial.all.find do |record|
          filial_name = normalize_text(record.name)
          filial_name == normalized || filial_name.include?(normalized) || normalized.include?(filial_name)
        end

        filial&.name || raise(Error, 'Destino inválido. Use Serra da Mantiqueira ou Fattoria di Brauna.')
      end
    end
  end

  def nights_count
    (@checkout - @checkin).to_i
  end

  def parse_date(value)
    return value if value.is_a?(Date)
    return if value.blank?

    text = value.to_s.strip
    return Date.iso8601(text) if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    return Date.strptime(text, '%d/%m/%Y') if text.match?(/\A\d{2}\/\d{2}\/\d{4}\z/)

    Date.parse(text)
  rescue ArgumentError, TypeError
    nil
  end

  def money(value)
    number_to_currency(value.to_d, unit: 'R$ ', separator: ',', delimiter: '.')
  end

  def normalize_text(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, ' ')
        .squish
  end
end
