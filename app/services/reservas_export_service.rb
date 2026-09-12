# frozen_string_literal: true

require 'csv'

class ReservasExportService
  def self.to_csv(reservas)
    new(reservas).generate_csv
  end

  def initialize(reservas, include_operational_services: false)
    @reservas = reservas.includes(:cabana, :user, reserva_services: :service)
    @include_operational_services = include_operational_services
  end

  def generate_csv
    CSV.generate(headers: true, col_sep: ';', encoding: 'UTF-8') do |csv|
      csv << headers

      @reservas.each do |reserva|
        # Linha da reserva
        csv << reserva_row(reserva)

        # Linhas dos serviços
        exportable_reserva_services(reserva).each do |rs|
          csv << service_row(reserva, rs)
        end
      end

      operational_service_rows.each do |row|
        csv << row
      end
    end
  end

  def generate_array
    rows = []
    
    @reservas.each do |reserva|
      rows << reserva_row(reserva)
      
      exportable_reserva_services(reserva).each do |rs|
        rows << service_row(reserva, rs)
      end
    end

    rows.concat(operational_service_rows)

    rows
  end

  private

  def exportable_reserva_services(reserva)
    reserva.reserva_services.reject do |reserva_service|
      ServicePurchaseLateFeeCart.late_fee_record?(reserva_service)
    end
  end

  def operational_service_rows
    return [] unless @include_operational_services
    return [] unless defined?(OperationalServiceOccurrence)
    return [] unless OperationalServiceOccurrence.connection.data_source_exists?(OperationalServiceOccurrence.table_name)

    OperationalServiceOccurrence
      .exportable
      .includes(cabana: :filial)
      .order(:service_date, :stable_id)
      .map { |occurrence| operational_service_row(occurrence) }
  end

  def headers
    [
      'Tipo',
      'ID Reserva',
      'Cabana',
      'Filial',
      'Hóspede',
      'Email',
      'Telefone',
      'Check-in',
      'Check-out',
      'Noites',
      'Valor',
      'Status Pagamento',
      'Nome Serviço',
      'Data Serviço',
      'Quantidade',
      'Status Serviço',
      'Valor Serviço',
      'Observação',
      'Data Criação',
      'Observação de Serviços',
      'Grupo Criado',
      'Nome Real do Hóspede',
      'Telefone Real do Hóspede',
      'PDF Fotos',
      'E-mail Real do Hóspede',
      'Canal da Reserva'
    ]
  end

  def reserva_row(reserva)
    noites = (reserva.end_date - reserva.start_date).to_i rescue 0
    
    [
      'Reserva',
      reserva.id,
      reserva.cabana&.name,
      reserva.cabana&.filial&.name,
      reserva.user&.name || reserva.user&.email,
      reserva.user&.email,
      reserva.user&.telephone,
      format_date(reserva.start_date),
      format_date(reserva.end_date),
      noites,
      format_currency(reserva.total_price),
      translate_status(reserva.payment_status),
      '-',
      '-',
      '-',
      '-',
      '-',
      reserva.observation,
      format_datetime(reserva.created_at),
      '-',
      group_created_label(reserva),
      reserva.guest_name,
      reserva.guest_phone,
      '-',
      reserva.guest_email,
      source_channel(reserva)
    ]
  end

  def service_row(reserva, rs)
    [
      'Serviço',
      reserva.id,
      reserva.cabana&.name,
      reserva.cabana&.filial&.name,
      reserva.user&.name || reserva.user&.email,
      reserva.user&.email,
      reserva.user&.telephone,
      '-',
      '-',
      '-',
      '-',
      '-',
      rs.service&.name,
      format_date(rs.service_date),
      rs.quantity,
      rs.cancelled? ? 'Cancelado' : 'Ativo',
      format_currency((rs.unit_price_paid || rs.service&.price_for(reserva)).to_f * rs.quantity.to_i),
      '-',
      format_datetime(rs.created_at),
      rs.visible_observation.presence || '-',
      group_created_label(reserva),
      reserva.guest_name,
      reserva.guest_phone,
      rs.photo_print_pdf_download_url.presence || '-',
      reserva.guest_email,
      source_channel(reserva)
    ]
  end

  def operational_service_row(occurrence)
    cabana = occurrence.cabana
    filial = occurrence.filial || cabana&.filial

    [
      'Serviço',
      occurrence.stable_id,
      cabana&.name,
      filial&.name,
      operational_guest_name(occurrence),
      '-',
      '-',
      '-',
      '-',
      '-',
      '-',
      '-',
      occurrence.name,
      format_date(occurrence.service_date),
      1,
      occurrence.cancelled? ? 'Cancelado' : 'Ativo',
      format_currency(0),
      occurrence.cancelled? ? occurrence.cancellation_reason.presence || '-' : '-',
      format_datetime(occurrence.created_at),
      '-',
      '-',
      '-',
      '-',
      '-',
      '-',
      '-'
    ]
  end

  def operational_guest_name(occurrence)
    occurrence.kind == 'recurring_maintenance' ? 'Manutenção' : 'Holmy'
  end

  def format_date(date)
    return '-' unless date
    date.strftime('%d/%m/%Y')
  end

  def format_datetime(datetime)
    return '-' unless datetime
    datetime.strftime('%d/%m/%Y %H:%M')
  end

  def format_currency(value)
    return 'R$ 0,00' unless value
    "R$ #{sprintf('%.2f', value).gsub('.', ',')}"
  end

  def translate_status(status)
    translations = {
      'pending' => 'Pendente',
      'waiting_payment' => 'Aguardando Pagamento',
      'paid' => 'Pago',
      'canceled' => 'Cancelado',
      'refused' => 'Recusado'
    }
    translations[status] || status
  end

  def group_created_label(reserva)
    reserva.group_created? ? 'Sim' : 'Não'
  end

  def source_channel(reserva)
    reserva.source_channel.presence || reserva.inferred_source_channel
  end
end
