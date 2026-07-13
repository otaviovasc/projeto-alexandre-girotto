# frozen_string_literal: true

require 'csv'

class ReservasExportService
  def self.to_csv(reservas)
    new(reservas).generate_csv
  end

  def initialize(reservas)
    @reservas = reservas.includes(:cabana, :user, reserva_services: :service)
  end

  def generate_csv
    CSV.generate(headers: true, col_sep: ';', encoding: 'UTF-8') do |csv|
      csv << headers

      @reservas.each do |reserva|
        # Linha da reserva
        csv << reserva_row(reserva)

        # Linhas dos serviços
        reserva.reserva_services.each do |rs|
          csv << service_row(reserva, rs)
        end
      end
    end
  end

  def generate_array
    rows = []
    
    @reservas.each do |reserva|
      rows << reserva_row(reserva)
      
      reserva.reserva_services.each do |rs|
        rows << service_row(reserva, rs)
      end
    end
    
    rows
  end

  private

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
      'PDF Fotos'
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
      '-'
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
      rs.observation.presence || '-',
      group_created_label(reserva),
      reserva.guest_name,
      reserva.guest_phone,
      rs.photo_print_pdf_download_url.presence || '-'
    ]
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
end
