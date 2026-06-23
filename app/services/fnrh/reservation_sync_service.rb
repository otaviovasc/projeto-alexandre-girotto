module Fnrh
  class ReservationSyncService
    def initialize(reserva, source: 'system')
      @reserva = reserva
      @source = source
    end

    def call(force: false)
      return false unless force || Configuration.enabled?
      return mark_not_eligible unless @reserva.fnrh_eligible?

      @reserva.fnrh_reservation_id.present? ? update_reservation : create_reservation
      true
    rescue => e
      record_error(e)
      false
    end

    private

    def client
      @client ||= Client.build(@reserva.cabana.filial)
    end

    def create_reservation
      result = client.create_reservation(@reserva)
      now = Time.current

      @reserva.update_columns(
        fnrh_status: result.fetch(:status),
        fnrh_reservation_id: result.fetch(:reservation_id),
        fnrh_precheckin_url: result.fetch(:precheckin_url),
        fnrh_scheduled_checkin_at: Schedule.checkin_at(@reserva),
        fnrh_synced_at: now,
        fnrh_last_error: nil,
        updated_at: now
      )
      record_event('reservation_created', 'success', 'Reserva criada na FNRH')
    end

    def update_reservation
      client.update_reservation(@reserva)
      now = Time.current
      @reserva.update_columns(
        fnrh_scheduled_checkin_at: Schedule.checkin_at(@reserva),
        fnrh_synced_at: now,
        fnrh_last_error: nil,
        updated_at: now
      )
      record_event('reservation_updated', 'success', 'Reserva atualizada na FNRH')
    end

    def mark_not_eligible
      return false if @reserva.fnrh_reservation_id.present?
      return false if @reserva.fnrh_status == 'not_eligible'

      @reserva.update_column(:fnrh_status, 'not_eligible')
      false
    end

    def record_error(error)
      now = Time.current
      @reserva.update_columns(fnrh_status: 'error', fnrh_last_error: error.message, updated_at: now)
      record_event('sync_error', 'error', error.message)
    end

    def record_event(event_type, status, message)
      @reserva.fnrh_events.create!(
        event_type: event_type,
        source: @source,
        status: status,
        message: message,
        occurred_at: Time.current
      )
    end
  end
end
