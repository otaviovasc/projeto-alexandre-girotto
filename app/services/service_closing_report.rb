# frozen_string_literal: true

class ServiceClosingReport
  DELIVERY_FEE = 30.to_d
  CHECKOUT_CLEANING_FEE = 45.to_d

  SLOT_LABELS = {
    morning: 'Manhã',
    lunch: 'Almoço',
    mid: '13h às 16h',
    after: 'Após 16h',
    night: 'Noite'
  }.freeze

  MEAL_KINDS = %i[
    cafe_da_manha almoco jantar fondue piquenique espumante tabua vinho bebida comida
  ].freeze

  def initialize(month: Date.current.prev_month)
    @month = month.to_date
    @start_date = @month.beginning_of_month
    @end_date = [@month.end_of_month, Date.current].min
  end

  attr_reader :start_date, :end_date

  def filial_reports
    rows = report_rows
    rows.group_by { |row| row[:filial] }.map do |filial, filial_rows|
      provider_rows = filial_rows
                      .group_by { |row| row[:provider] }
                      .map { |provider, provider_group| provider_summary(provider, provider_group) }
                      .sort_by { |row| row[:provider].to_s }

      {
        filial: filial,
        providers: provider_rows,
        total: provider_rows.sum { |row| row[:total] }
      }
    end.sort_by { |row| row[:filial].to_s }
  end

  def total
    filial_reports.sum { |report| report[:total] }
  end

  private

  def report_rows
    base_rows + delivery_rows
  end

  def reserva_services
    @reserva_services ||= ReservaService
                          .active_services
                          .includes(:service, reserva: [{ cabana: :filial }, :user])
                          .joins(:reserva)
                          .merge(Reserva.integration_ready)
                          .where(service_date: start_date..end_date)
                          .where('reserva_services.service_date <= ?', Date.current)
  end

  def base_rows
    reserva_services.each_with_object([]) do |reserva_service, rows|
      service = reserva_service.service
      kind = service_kind(service.name)
      next unless reportable_kind?(kind)

      filial_name = reserva_service.reserva.cabana.filial.name
      brauna = brauna?(filial_name)
      quantity = reserva_service.quantity.to_i
      quantity = 1 if quantity <= 0
      partner_total = partner_price(service) * quantity
      provider = provider_for(filial_name, kind)
      total = closing_total_for(reserva_service, kind, partner_total, brauna)
      next if provider.blank? || total.zero?

      rows << build_row(
        reserva_service: reserva_service,
        kind: kind,
        provider: provider,
        total: total,
        quantity: quantity,
        note: note_for(kind, brauna)
      )
    end
  end

  def delivery_rows
    grouped_delivery_services.map do |group_key, services|
      first_service = services.first
      reserva = first_service.reserva
      kind = service_kind(first_service.service.name)

      build_row(
        reserva_service: first_service,
        kind: kind,
        provider: 'Rubinho',
        total: DELIVERY_FEE,
        quantity: 1,
        note: "Entrega agrupada: #{services.size} refeição(ões) no mesmo período",
        delivery_group_key: group_key
      )
    end
  end

  def grouped_delivery_services
    reserva_services
      .select { |reserva_service| brauna_meal?(reserva_service) }
      .group_by { |reserva_service| delivery_group_key(reserva_service) }
  end

  def brauna_meal?(reserva_service)
    brauna?(reserva_service.reserva.cabana.filial.name) &&
      MEAL_KINDS.include?(service_kind(reserva_service.service.name))
  end

  def delivery_group_key(reserva_service)
    kind = service_kind(reserva_service.service.name)
    [
      reserva_service.reserva.cabana_id,
      reserva_service.service_date,
      slot_for(kind)
    ]
  end

  def build_row(reserva_service:, kind:, provider:, total:, quantity:, note:, delivery_group_key: nil)
    reserva = reserva_service.reserva
    {
      filial: reserva.cabana.filial.name,
      provider: provider,
      service_name: reserva_service.service.name,
      service_kind: kind,
      slot: slot_for(kind),
      slot_label: SLOT_LABELS[slot_for(kind)] || '-',
      service_date: reserva_service.service_date,
      cabana: reserva.cabana.name,
      reserva_id: reserva.id,
      guest: reserva.guest_name.presence || reserva.user.name.presence || reserva.user.email,
      quantity: quantity,
      total: total.to_d,
      note: note,
      delivery_group_key: delivery_group_key
    }
  end

  def provider_summary(provider, rows)
    {
      provider: provider,
      total: rows.sum { |row| row[:total] },
      rows: rows.sort_by { |row| [row[:service_date], row[:cabana].to_s, row[:slot].to_s, row[:service_name].to_s] }
    }
  end

  def closing_total_for(reserva_service, kind, partner_total, brauna)
    return CHECKOUT_CLEANING_FEE if checkout_cleaning?(kind)
    return partner_total unless brauna && MEAL_KINDS.include?(kind)

    [partner_total - delivery_discount_for(reserva_service), 0.to_d].max
  end

  def delivery_discount_for(reserva_service)
    group = grouped_delivery_services[delivery_group_key(reserva_service)]
    return DELIVERY_FEE if group.blank?

    DELIVERY_FEE / group.size
  end

  def note_for(kind, brauna)
    return 'Check-out' if checkout_cleaning?(kind)
    return 'Valor de parceria - entrega Rubinho' if brauna && MEAL_KINDS.include?(kind)

    'Valor de parceria'
  end

  def reportable_kind?(kind)
    return true if checkout_cleaning?(kind)

    kind.in?(%i[
      cafe_da_manha almoco jantar fondue piquenique espumante tabua vinho bebida comida
      passeio_a_cavalo trilha massagem fotos petalas bicicletas
    ])
  end

  def checkout_cleaning?(kind)
    kind == :limpeza_saida
  end

  def provider_for(filial_name, kind)
    return 'Manutenção' if checkout_cleaning?(kind)

    if brauna?(filial_name)
      return 'Maykha' if kind == :tabua
      return 'Andreia' if MEAL_KINDS.include?(kind)
      return 'Fabiana' if kind == :massagem
      return 'Girotto' if kind.in?(%i[passeio_a_cavalo trilha fotos petalas bicicletas])
    else
      return 'Girotto' if kind.in?(%i[passeio_a_cavalo trilha])
      return 'Carmen / Bruna' if kind.in?(%i[petalas espumante fotos])
      return 'Bruna' if MEAL_KINDS.include?(kind) || kind == :massagem || kind == :bicicletas
    end

    nil
  end

  def service_kind(service_name)
    name = normalize(service_name)

    return :limpeza_saida if name.include?('limpeza') && (name.include?('saida') || name.include?('check out') || name.include?('checkout'))
    return :limpeza_entrada if name.include?('limpeza')
    return :bicicletas if name.include?('bicicleta') || name.include?('mountain bike') || name.include?('mountainbike')
    return :passeio_a_cavalo if name.include?('passeio a cavalo') || name.include?('cavalo')
    return :trilha if name.include?('trilha')
    return :cobrar if name.include?('cobrar')
    return :avaliacao if name.include?('avaliacao')
    return :cafe_da_manha if name.include?('cafe')
    return :almoco if name.include?('almoco')
    return :jantar if name.include?('jantar')
    return :fondue if name.include?('fondue')
    return :piquenique if name.include?('piquenique')
    return :espumante if name.include?('espumante')
    return :petalas if name.include?('petala') || name.include?('luzinha')
    return :fotos if name.include?('foto')
    return :massagem if name.include?('massagem')
    return :tabua if name.include?('tabua') || name.include?('frios')
    return :vinho if name.include?('vinho')
    return :bebida if name.match?(/\b(suco|cerveja|agua|drink|bebida)\b/)
    return :comida if name.match?(/\b(comida|sobremesa|doce|bolo|queijo|salame|fruta)\b/)

    :outros
  end

  def slot_for(kind)
    case kind
    when :cafe_da_manha, :passeio_a_cavalo, :trilha
      :morning
    when :almoco
      :lunch
    when :jantar, :fondue, :tabua, :vinho
      :night
    when :cobrar, :avaliacao
      :after
    else
      :mid
    end
  end

  def partner_price(service)
    (service.partner_price || service.price || 0).to_d
  end

  def brauna?(filial_name)
    normalize(filial_name).include?('fattoria di brauna')
  end

  def normalize(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[\u{1F000}-\u{1FAFF}\uFE0F]/, ' ')
        .gsub(/^\s*\(\d+\)\s*/, ' ')
        .gsub(/\((sp|mg)\)/, ' ')
        .gsub(/[^a-z0-9]+/, ' ')
        .squish
  end
end
