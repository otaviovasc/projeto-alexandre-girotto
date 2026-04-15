require 'open-uri'
require 'icalendar'

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
          ics_content = URI.parse(url).open.read
          calendars = Icalendar::Calendar.parse(ics_content)
          calendar = calendars.first
          next unless calendar

          # Coleta todos os UIDs válidos desta importação
          uids_importados = []

          user = User.find_or_create_by!(email: "#{platform}@importado.com") do |u|
            u.name = platform.capitalize
            u.telephone = "00000000#{platform.hash % 10000}"
            u.password = "password"
            u.password_confirmation = "password"
          end

          calendar.events.each do |event|
            start_date = event.dtstart.to_date
            end_date   = event.dtend.to_date
            uid        = event.uid.to_s.strip

            # Airbnb adiciona 1 dia de buffer antes e depois no iCal
            # Precisamos compensar para obter as datas reais da reserva
            if platform.downcase == 'airbnb'
              start_date = start_date + 1.day
              end_date   = end_date - 1.day
            end

            # Regras de corte
            next if uid.blank?
            next if start_date < Date.current
            next if start_date > Date.current + 11.months
            end_date = start_date + 1.day if end_date <= start_date

            uids_importados << uid

            # Busca reserva existente pelo UID da plataforma
            reserva_existente = Reserva.find_by(
              cabana_id: cabana.id,
              origem: platform,
              platform_uid: uid
            )

            if reserva_existente
              # Atualiza as datas se mudaram na plataforma
              if reserva_existente.start_date != start_date || reserva_existente.end_date != end_date
                reserva_existente.update!(
                  start_date: start_date,
                  end_date: end_date
                )
                Rails.logger.info "🔄 Reserva #{reserva_existente.id} atualizada: #{start_date} → #{end_date} (#{platform}, cabana #{cabana.id})"
              end
            else
              # Cria nova reserva com o UID da plataforma
              Reserva.create!(
                start_date: start_date,
                end_date: end_date,
                user: user,
                cabana: cabana,
                origem: platform,
                platform_uid: uid,
                payment_status: 'paid',
                total_price: 0.0,
                observation: "Importado via #{platform.capitalize} - #{cabana.name}"
              )
              Rails.logger.info "✅ Nova reserva criada: #{start_date} → #{end_date} (#{platform}, cabana #{cabana.id}, UID: #{uid})"
            end
          end

          # Remove reservas futuras cujos UIDs não apareceram mais no feed
          # (foram canceladas na plataforma)
          if uids_importados.any?
            reservas_obsoletas = Reserva.where(
              cabana_id: cabana.id,
              origem: platform
            ).where(
              "platform_uid IS NOT NULL AND start_date >= ?", Date.current
            ).where.not(
              platform_uid: uids_importados
            )

            reservas_obsoletas.each do |r|
              Rails.logger.info "🗑️ Reserva #{r.id} removida (cancelada na plataforma): #{r.start_date} → #{r.end_date} (#{platform}, cabana #{cabana.id}, UID: #{r.platform_uid})"
            end

            reservas_obsoletas.destroy_all
          end

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
end

