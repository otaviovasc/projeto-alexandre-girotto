module Fnrh
  class ReservationSyncService
    AUTOMATIC_SKIP_STATUSES = %w[precheckin_bypassed duplicate_in_fnrh].freeze
    DUPLICATE_CODE_MESSAGE = 'ja existe uma reserva com o codigo informado'.freeze

    def initialize(reserva, source: 'system')
      @reserva = reserva
      @source = source
    end

    def call(force: false)
      return false unless force || Configuration.enabled?

      @reserva.with_lock do
        @reserva.reload
        return false if AUTOMATIC_SKIP_STATUSES.include?(@reserva.fnrh_status) && !force
        return mark_not_eligible unless @reserva.fnrh_eligible?

        @reserva.fnrh_reservation_id.present? ? update_reservation : create_reservation
        true
      end
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
      duplicate = duplicate_code_error?(error)
      @reserva.update_columns(
        fnrh_status: duplicate ? 'duplicate_in_fnrh' : 'error',
        fnrh_last_error: error.message,
        updated_at: now
      )
      record_event(duplicate ? 'duplicate_reservation' : 'sync_error', 'error', error.message)
    end

    def duplicate_code_error?(error)
      I18n.transliterate(error.message.to_s).downcase.include?(DUPLICATE_CODE_MESSAGE)
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
