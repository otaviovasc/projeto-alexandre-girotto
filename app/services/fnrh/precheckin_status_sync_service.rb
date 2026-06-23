module Fnrh
  class PrecheckinStatusSyncService
    def initialize(reserva, source: 'system')
      @reserva = reserva
      @source = source
    end

    def call
      return false unless @reserva.fnrh_reservation_id.present?
      return true if @reserva.fnrh_information_released?

      result = client.precheckin_status(@reserva)
      return false unless result[:completed]

      TransitionService.new(@reserva, source: @source).complete_precheckin(
        message: 'Pré-check-in confirmado pela FNRH',
        metadata: { statuses: result[:statuses] }
      )
      true
    rescue => e
      @reserva.update_columns(fnrh_last_error: e.message, updated_at: Time.current)
      @reserva.fnrh_events.create!(
        event_type: 'precheckin_status_error',
        source: @source,
        status: 'error',
        message: e.message,
        occurred_at: Time.current
      )
      false
    end

    private

    def client
      @client ||= Client.build(@reserva.cabana.filial)
    end
  end
end
