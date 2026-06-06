class ReservationServicesDateShifter
  def initialize(reserva, old_start_date:, new_start_date:)
    @reserva = reserva
    @old_start_date = old_start_date&.to_date
    @new_start_date = new_start_date&.to_date
  end

  def call
    return unless @reserva && @old_start_date && @new_start_date

    @reserva.reserva_services.includes(:service).find_each do |reserva_service|
      next if skipped_service?(reserva_service)
      next unless reserva_service.service_date

      offset = (reserva_service.service_date - @old_start_date).to_i
      reserva_service.update!(service_date: @new_start_date + offset)
    end
  end

  private

  def skipped_service?(reserva_service)
    reserva_service.cancelled? ||
      CleaningServicesAssigner.cleaning_service?(reserva_service.service) ||
      BreakfastServicesAssigner.included_breakfast_service?(reserva_service)
  end
end
