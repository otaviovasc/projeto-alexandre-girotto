class OfficialQuoteApi
  class Error < StandardError; end

  attr_reader :checkin, :checkout

  def initialize(params: nil, destino: nil, checkin: nil, checkout: nil, cabana: nil, details: nil,
                 pricing: OfficialSitePricing.new, services_catalog: OfficialServicesCatalog.new)
    @params = normalize_params(params)
    @params[:destino] ||= destino if destino.present?
    @params[:checkin] ||= checkin if checkin.present?
    @params[:checkout] ||= checkout if checkout.present?
    @params[:cabana] ||= cabana if cabana.present?
    @params[:details] = details unless details.nil?
    @pricing = pricing
    @services_catalog = services_catalog
  end

  def call
    load_inputs
    validate_inputs

    cabanas = matching_cabanas
    raise Error, 'Nenhuma cabana encontrada para esse destino.' if cabanas.blank?

    {
      ok: true,
      destino: destination_name,
      checkin: @checkin.to_s,
      checkout: @checkout.to_s,
      noites: nights_count,
      generated_at: Time.current.iso8601,
      fontes: {
        precos: 'Google Sheets',
        disponibilidade: 'Render',
        servicos: 'Render'
      },
      cabanas: cabanas.map { |cabana| quote_for(cabana) }
    }
  end

  private

  def normalize_params(params)
    return {}.with_indifferent_access if params.blank?

    raw =
      if params.respond_to?(:to_unsafe_h)
        params.to_unsafe_h
      else
        params.to_h
      end

    raw.with_indifferent_access
  end

  def load_inputs
    @destination = value_for(:destino, :destination, :filial)
    @cabin_filter = value_for(:cabana, :cabin, :cabana_id, :cabin_id)
    @checkin = parse_date(value_for(:checkin, :entrada, :start_date))
    @checkout = parse_date(value_for(:checkout, :saida, :end_date))
    @details = truthy?(value_for(:detalhes, :details))
  end

  def value_for(*keys)
    keys.each do |key|
      value = @params[key]
      return value if value.present?
    end
    nil
  end

  def validate_inputs
    raise Error, 'Informe check-in e check-out em formato valido.' if @checkin.blank? || @checkout.blank?
    raise Error, 'O check-out precisa ser depois do check-in.' if @checkout <= @checkin
    raise Error, 'O check-in nao pode estar no passado.' if @checkin < Date.current

    destination_name if @destination.present?
  end

  def matching_cabanas
    scope = Cabana.includes(:filial).order(:name)
    scope = scope.where(id: @cabin_filter) if numeric?(@cabin_filter)

    scope.to_a.select do |cabana|
      matches_destination?(cabana) && matches_cabana?(cabana)
    end
  end

  def quote_for(cabana)
    pricing_quote = @pricing.quote(
      cabana: cabana,
      start_date: @checkin,
      end_date: @checkout
    )

    available = available_for_range?(cabana)
    stay_total = pricing_quote[:stay_total] || pricing_quote[:total]
    minimum_nights = pricing_quote[:minimum] || pricing_quote[:minimum_nights]
    minimum_ok = pricing_quote[:meets_minimum] != false
    reasons = []
    reasons << 'Periodo indisponivel no calendario.' unless available
    reasons << pricing_quote[:minimum_message] if pricing_quote[:minimum_message].present?

    {
      id: cabana.id,
      nome: cabana.name,
      nome_publico: public_cabin_name(cabana),
      destino: cabana.filial&.name,
      filial_id: cabana.filial_id,
      disponivel: available && minimum_ok,
      status: available && minimum_ok ? 'disponivel' : 'indisponivel',
      motivos: reasons,
      hospedagem: decimal_to_float(stay_total),
      hospedagem_formatada: money(stay_total),
      noites: nights_count,
      minimo_diarias: minimum_nights,
      minimo_diarias_ok: minimum_ok,
      servicos: services_payload(cabana.filial)
    }.tap do |payload|
      payload[:diarias] = nights_payload(pricing_quote[:nights]) if @details
    end
  end

  def available_for_range?(cabana)
    if @pricing.respond_to?(:available?)
      @pricing.available?(cabana: cabana, start_date: @checkin, end_date: @checkout)
    else
      Reserva.new(cabana: cabana, start_date: @checkin, end_date: @checkout).available?
    end
  end

  def services_payload(filial)
    @services_catalog.for_filial(filial).map do |service|
      service.merge(
        preco: decimal_to_float(service[:preco]),
        preco_formatado: money(service[:preco])
      )
    end
  end

  def nights_payload(nights)
    Array(nights).map do |night|
      {
        data: night[:date].to_s,
        valor: decimal_to_float(night[:price]),
        valor_formatado: money(night[:price]),
        preco: decimal_to_float(night[:price]),
        preco_formatado: money(night[:price]),
        tipo: night[:weekend] ? 'fim_de_semana' : 'semana',
        fim_de_semana: night[:weekend],
        temporada: night[:season],
        feriado: night[:holiday],
        nome_feriado: night[:holiday_name],
        data_feriado: night[:holiday_date]
      }
    end
  end

  def public_cabin_name(cabana)
    if cabana.respond_to?(:guest_display_name)
      cabana.guest_display_name
    else
      cabana.name
    end
  end

  def destination_name
    return 'Todos' if @destination.blank?

    @destination_name ||= begin
      normalized = normalize_text(@destination)

      case normalized
      when /brauna|fattoria|sp|sao paulo/
        'Fattoria di Brauna'
      when /serra|mantiqueira|marmelopolis|minas|mg/
        'Serra da Mantiqueira'
      else
        filial = Filial.all.find { |record| normalize_text(record.name) == normalized }
        raise Error, 'Destino nao encontrado.' unless filial

        filial.name
      end
    end
  end

  def matches_destination?(cabana)
    target = destination_name
    return true if target == 'Todos'

    normalize_text(cabana.filial&.name) == normalize_text(target)
  end

  def matches_cabana?(cabana)
    return true if @cabin_filter.blank? || numeric?(@cabin_filter)

    target = normalize_text(@cabin_filter)
    names = [cabana.name, public_cabin_name(cabana)].compact.map { |name| normalize_text(name) }
    names.any? { |name| name == target || name.include?(target) || target.include?(name) }
  end

  def numeric?(value)
    value.to_s.match?(/\A\d+\z/)
  end

  def parse_date(value)
    return value.to_date if value.respond_to?(:to_date)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    Date.strptime(value.to_s, '%d/%m/%Y')
  rescue ArgumentError
    nil
  end

  def nights_count
    (@checkout - @checkin).to_i
  end

  def decimal_to_float(value)
    BigDecimal(value.to_s).to_f
  end

  def money(value)
    ActionController::Base.helpers.number_to_currency(
      value.to_d,
      unit: 'R$ ',
      separator: ',',
      delimiter: '.'
    )
  end

  def normalize_text(value)
    I18n.transliterate(value.to_s).downcase.strip
  end

  def truthy?(value)
    value.to_s.in?(%w[1 true sim yes])
  end
end
