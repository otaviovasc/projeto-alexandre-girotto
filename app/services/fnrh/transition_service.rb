module Fnrh
  class TransitionService
    def initialize(reserva, source: 'manual')
      @reserva = reserva
      @source = source
    end

    def complete_precheckin(at: Time.current, message: 'Pré-check-in concluído na FNRH', metadata: {})
      ensure_external_reservation!
      raise 'Reserva cancelada ou marcada como no-show' if @reserva.fnrh_status.in?(%w[cancelled no_show])
      return true if @reserva.fnrh_status.in?(%w[precheckin_completed precheckin_bypassed checked_in checked_out])

      transition!(
        event_type: 'precheckin_completed',
        status: 'precheckin_completed',
        timestamp_column: :fnrh_precheckin_at,
        at: at,
        message: message,
        metadata: metadata
      )
    end

    def bypass_precheckin(at: Time.current)
      raise 'Reserva cancelada ou marcada como no-show' if @reserva.fnrh_status.in?(%w[cancelled no_show])
      return true if @reserva.fnrh_information_released?

      now = Time.current
      @reserva.update_columns(
        fnrh_status: 'precheckin_bypassed',
        fnrh_precheckin_at: at,
        fnrh_last_error: nil,
        updated_at: now
      )
      @reserva.fnrh_events.create!(
        event_type: 'precheckin_bypassed',
        source: @source,
        status: 'success',
        message: 'FNRH pulada manualmente',
        metadata: { internal_release: true },
        occurred_at: at
      )
      true
    end

    def check_in(at: Time.current)
      ensure_external_reservation!
      raise 'Reserva cancelada ou marcada como no-show' if @reserva.fnrh_status.in?(%w[cancelled no_show])
      return true if @reserva.fnrh_status.in?(%w[checked_in checked_out])

      client.check_in(@reserva, at: at)
      transition!(
        event_type: 'checkin',
        status: 'checked_in',
        timestamp_column: :fnrh_checkin_at,
        at: at,
        message: "Check-in #{@source == 'automatic' ? 'automático' : 'manual'} realizado",
        metadata: {}
      )
    end

    def check_out(at: Time.current)
      ensure_external_reservation!
      raise 'O check-in precisa ser realizado antes do checkout' unless @reserva.fnrh_status == 'checked_in'

      client.check_out(@reserva, at: at)
      transition!(
        event_type: 'checkout',
        status: 'checked_out',
        timestamp_column: :fnrh_checkout_at,
        at: at,
        message: "Checkout #{@source == 'automatic' ? 'automático' : 'manual'} realizado",
        metadata: {}
      )
    end

    def no_show(at: Time.current)
      ensure_external_reservation!
      raise 'Não é possível marcar no-show após o check-in' if @reserva.fnrh_status.in?(%w[checked_in checked_out])

      client.no_show(@reserva, at: at)
      transition!(
        event_type: 'no_show',
        status: 'no_show',
        timestamp_column: :fnrh_no_show_at,
        at: at,
        message: 'Reserva marcada como no-show',
        metadata: {}
      )
    end

    def cancel(at: Time.current)
      return true if @reserva.fnrh_reservation_id.blank? || @reserva.fnrh_status == 'cancelled'

      client.cancel(@reserva, at: at)
      transition!(
        event_type: 'cancellation',
        status: 'cancelled',
        timestamp_column: :fnrh_cancelled_at,
        at: at,
        message: 'Reserva cancelada na FNRH',
        metadata: {}
      )
    end

    private

    def client
      @client ||= Client.build(@reserva.cabana.filial)
    end

    def ensure_external_reservation!
      raise 'Reserva ainda não foi criada na FNRH' if @reserva.fnrh_reservation_id.blank?
    end

    def transition!(event_type:, status:, timestamp_column:, at:, message:, metadata:)
      now = Time.current
      @reserva.update_columns(
        fnrh_status: status,
        timestamp_column => at,
        fnrh_synced_at: now,
        fnrh_last_error: nil,
        updated_at: now
      )
      @reserva.fnrh_events.create!(
        event_type: event_type,
        source: @source,
        status: 'success',
        message: message,
        metadata: metadata,
        occurred_at: at
      )
      true
    rescue => e
      @reserva.update_columns(fnrh_status: 'error', fnrh_last_error: e.message, updated_at: Time.current)
      @reserva.fnrh_events.create!(
        event_type: "#{event_type}_error",
        source: @source,
        status: 'error',
        message: e.message,
        occurred_at: Time.current
      )
      raise
    end
  end
end
