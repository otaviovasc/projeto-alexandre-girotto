class ImportadorDeReservasJob
  def self.run
    totals = Hash.new(0)

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
          result = IcalReservationImporter.new(cabana: cabana, platform: platform, url: url).call
          totals[:created] += result.created
          totals[:updated] += result.updated
          totals[:missing] += result.missing
        rescue => e
          Rails.logger.error "Erro ao importar reservas para cabana #{cabana.id} (#{platform}): #{e.message}"
        end
      end
    end

    if totals.values.sum.zero?
      Rails.logger.info "📊 Nenhuma alteração de reservas via iCal; Google Sheets não sincronizado."
      return
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
    ensure
      GC.start
    end
  end

  def self.cancel_missing_imported_reservas?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('IMPORT_CANCEL_MISSING_RESERVAS', 'false'))
  end
end
