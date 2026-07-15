# frozen_string_literal: true

# Google Sheets Export Service
# 
# Para usar esta funcionalidade, você precisa:
# 1. Criar um projeto no Google Cloud Console (https://console.cloud.google.com)
# 2. Ativar a Google Sheets API
# 3. Criar uma Service Account e baixar as credenciais JSON
# 4. Salvar o arquivo como credentials/google_sheets_credentials.json
# 5. Criar uma planilha e compartilhar com o email da Service Account
# 6. Adicionar as variáveis de ambiente:
#    - GOOGLE_SHEETS_SPREADSHEET_ID: ID da planilha (da URL)
#    - GOOGLE_SHEETS_CANCELED_SPREADSHEET_ID: ID da planilha separada de histórico de canceladas
#    - GOOGLE_SHEETS_CREDENTIALS_PATH: caminho para o arquivo de credenciais
#
# Depois de configurado, descomente a gem no Gemfile:
# gem 'google-api-client'

require 'csv'

class GoogleSheetsExportService
  SCOPES = ['https://www.googleapis.com/auth/spreadsheets'].freeze
  DEFAULT_CANCELED_HISTORY_SPREADSHEET_ID = '1jTqpEW5hDKyH5zp9F2Q6kutvNx7P-VkdGUEpwrKWO04'
  CANCELED_HISTORY_SHEET_TITLE = 'Canceladas'
  LEGACY_CANCELED_SHEET_TITLE = 'Reservas Canceladas'
  
  class << self
    def export_reservas(reservas)
      ready_reservas = if reservas.respond_to?(:where)
                         reservas.where(reservas: { payment_status: 'paid', blocks_availability: true })
                       else
                         Array(reservas).select(&:integration_ready?)
                       end

      new.export(ready_reservas)
    end

    def delete_reserva(reserva_id)
      new.delete_by_id(reserva_id)
    end

    def export_service_purchases(reserva_services)
      new.export_service_purchases(reserva_services)
    end

    def configured?
      spreadsheet_id.present? && (credentials_json_content.present? || (credentials_path.present? && File.exist?(credentials_path)))
    end

    def spreadsheet_id
      ENV['GOOGLE_SHEETS_SPREADSHEET_ID']
    end

    def canceled_history_spreadsheet_id
      ENV['GOOGLE_SHEETS_CANCELED_SPREADSHEET_ID'].presence || DEFAULT_CANCELED_HISTORY_SPREADSHEET_ID
    end

    def credentials_json_content
      ENV['GOOGLE_SHEETS_CREDENTIALS_JSON']
    end

    def credentials_path
      ENV['GOOGLE_SHEETS_CREDENTIALS_PATH'] || Rails.root.join('credentials', 'google_sheets_credentials.json').to_s
    end
  end

  def initialize
    @spreadsheet_id = self.class.spreadsheet_id
    @canceled_history_spreadsheet_id = self.class.canceled_history_spreadsheet_id
  end

  def export_service_purchases(reserva_services)
    return { success: false, error: 'Google Sheets nao configurado' } unless self.class.configured?

    reserva_services = Array(reserva_services).compact
    return { success: true, rows_updated: 0, message: 'Nenhuma compra de servico para exportar' } if reserva_services.empty?

    begin
      require 'google/apis/sheets_v4'
      require 'googleauth'
      require 'stringio'

      service = Google::Apis::SheetsV4::SheetsService.new
      service.client_options.application_name = 'Villaggio Girotto'
      service.authorization = authorize

      sheet_title = 'Compras de Servicos'
      ensure_sheet_exists!(service, sheet_title)
      ensure_service_purchases_headers!(service, sheet_title)

      rows = service_purchase_rows(reserva_services)
      value_range = Google::Apis::SheetsV4::ValueRange.new(values: rows)

      result = service.append_spreadsheet_value(
        @spreadsheet_id,
        quoted_range(sheet_title, 'A:G'),
        value_range,
        value_input_option: 'USER_ENTERED',
        insert_data_option: 'INSERT_ROWS'
      )

      {
        success: true,
        rows_updated: result.updates&.updated_rows || rows.size,
        message: "#{rows.size} compra(s) de servico exportada(s) para Google Sheets"
      }
    rescue => e
      Rails.logger.error "Google Sheets Service Purchases Export Error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  def export(reservas)
    return { success: false, error: 'Google Sheets não configurado' } unless self.class.configured?

    begin
      # Carrega a API do Google
      require 'google/apis/sheets_v4'
      require 'googleauth'
      require 'stringio'

      service = Google::Apis::SheetsV4::SheetsService.new
      service.client_options.application_name = 'Villaggio Girotto'
      service.authorization = authorize
      
      # ... (rest of export logic is fine, authorize is called here)

      # Prepara os dados
      export_service = ReservasExportService.new(reservas)
      headers = reservas_headers
      rows = export_service.generate_array

      # Limpa a planilha e insere novos dados
      clear_range = 'A:X'
      service.clear_values(@spreadsheet_id, clear_range)

      # Insere headers + dados
      all_data = [headers] + rows
      value_range = Google::Apis::SheetsV4::ValueRange.new(values: all_data)
      
      result = service.update_spreadsheet_value(
        @spreadsheet_id,
        'A1',
        value_range,
        value_input_option: 'USER_ENTERED'
      )
      clear_legacy_canceled_reservas_sheet(service)
      canceled_history_result = export_canceled_reservas_sheet(service)
      unless canceled_history_result[:success]
        Rails.logger.error "Google Sheets Canceled History Export Error: #{canceled_history_result[:error]}"
      end

      {
        success: true,
        rows_updated: result.updated_rows,
        message: "#{result.updated_rows} linhas exportadas para Google Sheets e histórico de canceladas sincronizado em planilha separada"
      }
    rescue => e
      Rails.logger.error "Google Sheets Export Error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Deleta todas as linhas que contêm o ID da reserva
  def delete_by_id(reserva_id)
    return { success: false, error: 'Google Sheets não configurado' } unless self.class.configured?

    begin
      require 'google/apis/sheets_v4'
      require 'googleauth'
      require 'stringio'

      service = Google::Apis::SheetsV4::SheetsService.new
      service.client_options.application_name = 'Villaggio Girotto'
      service.authorization = authorize

      # Busca todos os dados da planilha
      response = service.get_spreadsheet_values(@spreadsheet_id, 'A:W')
      rows = response.values || []

      # Encontra as linhas que contêm o ID da reserva (coluna B = índice 1)
      rows_to_delete = []
      rows.each_with_index do |row, index|
        # Coluna B (índice 1) contém o ID da reserva
        if row[1].to_s == reserva_id.to_s
          rows_to_delete << index
        end
      end

      if rows_to_delete.empty?
        return { success: true, message: 'Nenhuma linha encontrada para deletar' }
      end

      # Deleta as linhas de baixo para cima (para não afetar os índices)
      # Obtém o sheet ID (geralmente 0 para a primeira aba)
      spreadsheet = service.get_spreadsheet(@spreadsheet_id)
      sheet_id = spreadsheet.sheets.first.properties.sheet_id

      requests = rows_to_delete.sort.reverse.map do |row_index|
        {
          delete_dimension: {
            range: {
              sheet_id: sheet_id,
              dimension: 'ROWS',
              start_index: row_index,
              end_index: row_index + 1
            }
          }
        }
      end

      batch_update_request = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(requests: requests)
      service.batch_update_spreadsheet(@spreadsheet_id, batch_update_request)

      {
        success: true,
        rows_deleted: rows_to_delete.count,
        message: "#{rows_to_delete.count} linha(s) deletada(s) do Google Sheets"
      }
    rescue => e
      Rails.logger.error "Google Sheets Delete Error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  def reservas_headers
    [
      'Tipo', 'ID Reserva', 'Cabana', 'Filial', 'Hóspede', 'Email', 'Telefone',
      'Check-in', 'Check-out', 'Noites', 'Valor', 'Status Pagamento',
      'Nome Serviço', 'Data Serviço', 'Quantidade', 'Status Serviço',
      'Valor Serviço', 'Observação', 'Data Criação', 'Observação de Serviços',
      'Grupo Criado', 'Nome Real do Hóspede', 'Telefone Real do Hóspede', 'PDF Fotos'
    ]
  end

  def export_canceled_reservas_sheet(service)
    return { success: false, error: 'Planilha de histórico de canceladas não configurada' } if @canceled_history_spreadsheet_id.blank?

    canceled_reservas = Reserva
                        .canceled_for_history
                        .includes(:cabana, :user, :canceled_by, :reserva_payments, reserva_services: :service)
                        .order(canceled_at: :desc, updated_at: :desc)

    ensure_sheet_exists!(service, CANCELED_HISTORY_SHEET_TITLE, spreadsheet_id: @canceled_history_spreadsheet_id)
    service.clear_values(@canceled_history_spreadsheet_id, quoted_range(CANCELED_HISTORY_SHEET_TITLE, 'A:U'))
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [canceled_history_headers] + canceled_history_rows(canceled_reservas))
    result = service.update_spreadsheet_value(
      @canceled_history_spreadsheet_id,
      quoted_range(CANCELED_HISTORY_SHEET_TITLE, 'A1'),
      value_range,
      value_input_option: 'USER_ENTERED'
    )

    { success: true, rows_updated: result.updated_rows }
  rescue => e
    { success: false, error: e.message }
  end

  def clear_legacy_canceled_reservas_sheet(service)
    return unless sheet_exists?(service, @spreadsheet_id, LEGACY_CANCELED_SHEET_TITLE)

    service.clear_values(@spreadsheet_id, quoted_range(LEGACY_CANCELED_SHEET_TITLE, 'A:AA'))
  rescue => e
    Rails.logger.error "Google Sheets Legacy Canceled Sheet Clear Error: #{e.message}"
  end

  def canceled_history_headers
    [
      'ID Reserva',
      'Data cancelamento',
      'Hora cancelamento',
      'Motivo',
      'Tipo',
      'Teve pagamento?',
      'Status original',
      'Origem',
      'Cabana',
      'Filial',
      'Hospede',
      'Telefone',
      'Email',
      'Entrada',
      'Saida',
      'Valor reserva',
      'Valor pago',
      'Parcelas pagas',
      'Servicos',
      'Codigo iCal / Pagamento',
      'Observacoes'
    ]
  end

  def canceled_history_rows(canceled_reservas)
    canceled_reservas.map do |reserva|
      paid_payments = reserva.reserva_payments.select(&:paid?)
      paid_amount = paid_payments.sum { |payment| payment.amount.to_d }
      service_count = reserva.reserva_services.size

      [
        reserva.id,
        format_date(reserva.canceled_at),
        format_time(reserva.canceled_at),
        canceled_history_reason(reserva),
        canceled_history_type(reserva),
        paid_payments.any? ? 'Sim' : 'Não',
        'Cancelado',
        reserva.origem.presence || 'sistema',
        reserva.cabana&.name,
        reserva.cabana&.filial&.name,
        reserva.guest_name.presence || reserva.user&.name || reserva.user&.email,
        reserva.guest_phone.presence || reserva.user&.telephone,
        reserva.user&.email,
        format_date(reserva.start_date),
        format_date(reserva.end_date),
        format_currency(reserva.total_price),
        format_currency(paid_amount),
        paid_payments.size,
        "#{service_count} serviço(s)",
        canceled_history_codes(reserva),
        canceled_history_observation(reserva)
      ]
    end
  end

  def canceled_history_reason(reserva)
    reserva.cancellation_reason.presence || canceled_history_type(reserva)
  end

  def canceled_history_type(reserva)
    payments = reserva.reserva_payments
    return 'Pré-reserva sem pagamento' if payments.any? && payments.none?(&:paid?)
    return 'Reserva com pagamento' if payments.any?(&:paid?)
    return 'Reserva importada iCal' if reserva.origem.present? && reserva.origem != 'sistema'

    'Reserva real'
  end

  def canceled_history_codes(reserva)
    codes = [
      reserva.platform_uid,
      reserva.ical_uid,
      reserva.payment_link_id,
      reserva.payment_link_url,
      *reserva.reserva_payments.map(&:payment_order_code)
    ].compact_blank

    codes.uniq.join(' | ')
  end

  def canceled_history_observation(reserva)
    parts = [
      reserva.observation,
      ("Cancelado por #{reserva.canceled_by.name.presence || reserva.canceled_by.email}" if reserva.canceled_by),
      ("Criada em #{format_datetime(reserva.created_at)}" if reserva.created_at)
    ].compact_blank

    parts.join(' | ').presence || '-'
  end

  def ensure_sheet_exists!(service, sheet_title, spreadsheet_id: @spreadsheet_id)
    return if sheet_exists?(service, spreadsheet_id, sheet_title)

    request = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(
      requests: [
        {
          add_sheet: {
            properties: {
              title: sheet_title
            }
          }
        }
      ]
    )

    service.batch_update_spreadsheet(spreadsheet_id, request)
  end

  def sheet_exists?(service, spreadsheet_id, sheet_title)
    spreadsheet = service.get_spreadsheet(spreadsheet_id)
    sheet_exists = spreadsheet.sheets.any? { |sheet| sheet.properties.title == sheet_title }
    sheet_exists
  end

  def ensure_service_purchases_headers!(service, sheet_title)
    response = service.get_spreadsheet_values(@spreadsheet_id, quoted_range(sheet_title, 'A1:G1'))
    headers = ['ID DA RESERVA', 'NOME DO CLIENTE', 'SERVICO', 'QUANTIDADE', 'VALOR', 'OBSERVACAO', 'PDF FOTOS']
    current_headers = Array(response.values&.first)
    return if current_headers == headers

    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [headers])

    service.update_spreadsheet_value(
      @spreadsheet_id,
      quoted_range(sheet_title, 'A1:G1'),
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  end

  def service_purchase_rows(reserva_services)
    reserva_services.map do |reserva_service|
      [
        reserva_service.reserva_id,
        reserva_service.reserva.user.name,
        reserva_service.service.name,
        reserva_service.quantity,
        format_currency(reserva_service.total_paid || ((reserva_service.unit_price_paid || reserva_service.service.price_for(reserva_service.reserva) || 0) * (reserva_service.quantity || 1))),
        reserva_service.observation.presence || '-',
        reserva_service.photo_print_pdf_download_url.presence || '-'
      ]
    end
  end

  def format_currency(value)
    "R$ #{format('%.2f', value || 0).tr('.', ',')}"
  end

  def format_datetime(datetime)
    return '-' unless datetime

    datetime.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y %H:%M')
  end

  def format_date(date_or_time)
    return '-' unless date_or_time

    if date_or_time.respond_to?(:in_time_zone)
      date_or_time.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')
    else
      date_or_time.strftime('%d/%m/%Y')
    end
  end

  def format_time(datetime)
    return '-' unless datetime

    datetime.in_time_zone('America/Sao_Paulo').strftime('%H:%M')
  end

  def quoted_range(sheet_title, range)
    "'#{sheet_title}'!#{range}"
  end

  def authorize
    json_io = if self.class.credentials_json_content.present?
                StringIO.new(self.class.credentials_json_content)
              else
                File.open(self.class.credentials_path)
              end

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: json_io,
      scope: SCOPES
    )
  end
end
