class ClearStalePortalTimingNotes < ActiveRecord::Migration[7.0]
  CHECKIN_AFTERNOON_NOTE = "de tarde após check-in".freeze

  class MigrationReserva < ActiveRecord::Base
    self.table_name = "reservas"
  end

  class MigrationService < ActiveRecord::Base
    self.table_name = "services"
  end

  class MigrationReservaService < ActiveRecord::Base
    self.table_name = "reserva_services"

    belongs_to :reserva, class_name: "ClearStalePortalTimingNotes::MigrationReserva"
    belongs_to :service, class_name: "ClearStalePortalTimingNotes::MigrationService"
  end

  def up
    return unless table_exists?(:reserva_services) && table_exists?(:reservas) && table_exists?(:services)

    MigrationReservaService
      .includes(:reserva, :service)
      .where(observation: CHECKIN_AFTERNOON_NOTE)
      .find_each do |reserva_service|
        next unless automatic_checkin_note_service?(reserva_service.service)
        next if valid_checkin_note?(reserva_service)

        reserva_service.update_columns(observation: nil, updated_at: Time.current)
      end
  end

  def down
  end

  private

  def automatic_checkin_note_service?(service)
    normalized_name = I18n.transliterate(service&.name.to_s)
                          .downcase
                          .gsub(/[^a-z0-9]+/, " ")
                          .squish

    normalized_name.include?("trilha") ||
      normalized_name.include?("cavalo") ||
      normalized_name.include?("piquenique")
  end

  def valid_checkin_note?(reserva_service)
    reserva = reserva_service.reserva
    return false if reserva.blank? || reserva.start_date.blank? || reserva_service.service_date.blank?
    return false if reserva.early_checkin?

    reserva_service.service_date == reserva.start_date
  end
end
