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

          eventos = []

          # Lê todos os eventos do calendário
          calendar.events.each do |event|
            start_date = event.dtstart.to_date
            end_date   = event.dtend.to_date - 1.day # Airbnb envia DTEND exclusivo

            # Regras de corte
            next if start_date < Date.current
            next if start_date > Date.current + 11.months
            end_date = start_date + 1.day if end_date <= start_date

            eventos << [start_date, end_date]
          end

          # Ordena eventos por data de início
          eventos.sort_by!(&:first)

          # Mescla períodos sobrepostos ou colados
          merged = []
          eventos.each do |start_date, end_date|
            if merged.empty?
              merged << [start_date, end_date]
            else
              last_start, last_end = merged.last
              if start_date <= last_end + 1.day
                # Expande o período
                merged[-1] = [last_start, [last_end, end_date].max]
              else
                merged << [start_date, end_date]
              end
            end
          end

          # Cria ou atualiza reservas mescladas
          merged.each do |start_date, end_date|
            # Verifica se já existe reserva desse período e origem
            reserva_existente = Reserva.where(
              cabana_id: cabana.id,
              origem: platform
            ).where(
              "start_date <= ? AND end_date >= ?", end_date, start_date
            ).first

            user = User.find_or_create_by!(email: "#{platform}@importado.com") do |u|
              u.name = platform.capitalize
              u.telephone = "00000000#{platform.hash % 10000}"
              u.password = "password"
              u.password_confirmation = "password"
            end

            if reserva_existente
              # Atualiza datas para cobrir o período todo
              reserva_existente.update!(
                start_date: [reserva_existente.start_date, start_date].min,
                end_date: [reserva_existente.end_date, end_date].max
              )
            else
              # Cria nova reserva
              Reserva.create!(
                start_date: start_date,
                end_date: end_date,
                user: user,
                cabana: cabana,
                origem: platform,
                payment_status: 'paid',
                total_price: 0.0,
                observation: "Importado via #{platform.capitalize} - #{cabana.name}"
              )
            end
          end

        rescue => e
          Rails.logger.error "Erro ao importar reservas para cabana #{cabana.id} (#{platform}): #{e.message}"
        end
      end
    end
  end
end
