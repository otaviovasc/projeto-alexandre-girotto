class OfficialServicesCatalog
  include ActiveSupport::NumberHelper

  CATEGORY_ORDER = Service::PORTAL_CATEGORY_ORDER.each_with_index.to_h.freeze

  def all
    service_records.each_with_object({}) do |service, rows|
      key = catalog_key(service)
      rows[key] ||= aggregate_row_for(service)
      apply_destination_price(rows[key], service)
    end.values
       .map { |row| finalize_aggregate_row(row) }
       .sort_by { |row| sort_key(row) }
  end

  def for_filial(filial)
    return [] if filial.blank?

    service_records(filial: filial)
      .map { |service| service_row(service) }
      .sort_by { |row| sort_key(row) }
  end

  private

  def service_records(filial: nil)
    scope = Service.includes(:filial).where(show_in_marketplace: [true, nil])
    scope = scope.where(filial_id: filial.id) if filial.present?

    scope.order(:name).to_a.reject { |service| internal_service?(service) }
  end

  def internal_service?(service)
    CleaningServicesAssigner.cleaning_service?(service) ||
      ReservaService.free_date_service?(service) ||
      service.hidden_from_guests?
  end

  def service_row(service)
    price = price_for(service)
    name = display_name(service)
    destination = destination_for(service.filial)

    {
      id: service.id,
      categoria: service.portal_category,
      servico: name,
      nome: name,
      preco: price.to_f,
      preco_formatado: money(price),
      cobranca: billing_for(service),
      observacoes: service.description.to_s,
      descricao: description_for(service),
      filial: service.filial&.name.to_s,
      destino: destination_label(destination),
      disponivel: service.show_in_marketplace != false
    }
  end

  def aggregate_row_for(service)
    name = display_name(service)

    {
      id: nil,
      id_serra: nil,
      id_brauna: nil,
      categoria: service.portal_category,
      servico: name,
      nome: name,
      preco: nil,
      preco_serra: nil,
      preco_brauna: nil,
      preco_formatado: nil,
      disponivel_serra: false,
      disponivel_brauna: false,
      cobranca: billing_for(service),
      observacoes: service.description.to_s,
      descricao: description_for(service)
    }
  end

  def apply_destination_price(row, service)
    destination = destination_for(service.filial)
    price = price_for(service)

    row[:id] ||= service.id
    row[:preco] ||= price.to_f
    row[:preco_formatado] ||= money(price)
    row[:"id_#{destination}"] = service.id
    row[:"preco_#{destination}"] = price.to_f
    row[:"preco_#{destination}_formatado"] = money(price)
    row[:"disponivel_#{destination}"] = true
  end

  def finalize_aggregate_row(row)
    row[:preco] ||= row[:preco_serra] || row[:preco_brauna] || 0
    row[:preco_formatado] ||= money(row[:preco])
    row
  end

  def catalog_key(service)
    "#{normalize_text(display_name(service))}|#{normalize_text(service.portal_category)}"
  end

  def destination_for(filial)
    normalized_filial = normalize_text(filial&.name || filial)

    normalized_filial.include?('brauna') ? :brauna : :serra
  end

  def destination_label(destination)
    destination == :brauna ? 'Fattoria di Brauna' : 'Serra da Mantiqueira'
  end

  def sort_key(row)
    [CATEGORY_ORDER.fetch(row[:categoria], 99), normalize_text(row[:servico])]
  end

  def display_name(service)
    service.name.to_s
           .sub(/\A\(\d+\)\s*/, '')
           .sub(/\s+\((?:SP|MG)\)\z/i, '')
           .squish
  end

  def price_for(service)
    BigDecimal(service.price.to_s)
  rescue ArgumentError, TypeError
    0.to_d
  end

  def billing_for(service)
    name = normalize_text(display_name(service))

    return 'por diaria' if name.include?('bicic') || name.include?('cafe')
    return 'por refeicao' if name.include?('almoco') || name.include?('jantar')
    return 'por piquenique' if name.include?('piquenique')
    return 'por pedido' if name.include?('tabua') || name.include?('fondue')
    return 'por sessao' if name.include?('massagem')
    return 'por pacote' if name.include?('foto')
    return 'por unidade' if name.include?('espumante')
    return 'por montagem' if name.include?('petala') || name.include?('luzinha')

    'por pedido'
  end

  def description_for(service)
    service.description.presence || service_hint(service)
  end

  def service_hint(service)
    name = normalize_text(display_name(service))
    category = normalize_text(service.portal_category)

    return 'Valor por sessao, para 1 pessoa.' if name.include?('massagem 1') || name.include?('1 pessoa')
    return 'Valor por sessao, para 2 pessoas.' if name.include?('massagem 2') || name.include?('2 pessoas') || name.include?('duas pessoas')
    return 'Valor por diaria.' if name.include?('bicic')
    return 'Valor por diaria, para ate 2 pessoas.' if name.include?('cafe')
    return 'Valor por refeicao, para ate 2 pessoas.' if name.include?('almoco') || name.include?('jantar')
    return 'Valor por piquenique, para ate 2 pessoas.' if name.include?('piquenique')
    return 'Valor por pedido, para ate 2 pessoas.' if name.include?('tabua') || name.include?('fondue')
    return 'Valor por experiencia, para ate 2 pessoas.' if category.include?('passeios')
    return 'Valor por unidade.' if name.include?('espumante')
    return 'Pacote com ate 3 fotos impressas.' if name.include?('foto')
    return 'Valor por montagem.' if name.include?('petala') || name.include?('luzinha')

    'Valor por pedido.'
  end

  def money(value)
    number_to_currency(BigDecimal(value.to_s), unit: 'R$ ', separator: ',', delimiter: '.')
  rescue ArgumentError, TypeError
    number_to_currency(0, unit: 'R$ ', separator: ',', delimiter: '.')
  end

  def normalize_text(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, ' ')
        .squish
  end
end
