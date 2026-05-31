class ImportadorDeReservasJob
  def self.run
    Cabana.find_each do |cabana|
      import_links = {}

      # Lê links de importação salvos no campo import_links
      begin
        import_links = JSON.parse(cabana.import_links) if cabana.import_links.present?
      rescue JSON::ParserError
        next
      end

      import_links.each do |platform, url|
        begin
          IcalReservationImporter.new(cabana: cabana, platform: platform, url: url).call
        rescue => e
          Rails.logger.error "Erro ao importar reservas para cabana #{cabana.id} (#{platform}): #{e.message}"
        end
      end
    end

    # Sincroniza com Google Sheets após importação
    begin
      if GoogleSheetsExportService.configured?
        GoogleSheetsExportService.export_reservas(
          Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
        )
        Rails.logger.info "📊 Reservas sincronizadas com Google Sheets após importação"
      end
    rescue => e
      Rails.logger.error "Erro ao sincronizar com Google Sheets: #{e.message}"
    end
  end

  def self.cancel_missing_imported_reservas?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('IMPORT_CANCEL_MISSING_RESERVAS', 'false'))
  end
end
