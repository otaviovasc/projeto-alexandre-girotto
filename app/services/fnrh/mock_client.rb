require 'securerandom'

module Fnrh
  class MockClient
    def initialize(filial)
      @filial = filial
    end

    def create_reservation(reserva)
      reservation_id = SecureRandom.uuid

      {
        reservation_id: reservation_id,
        precheckin_url: "/fnrh-simulacao/precheckin/#{reservation_id}",
        status: 'awaiting_precheckin'
      }
    end

    def update_reservation(_reserva)
      { success: true }
    end

    def check_in(_reserva, at:)
      { success: true, occurred_at: at }
    end

    def check_out(_reserva, at:)
      { success: true, occurred_at: at }
    end

    def no_show(_reserva, at:)
      { success: true, occurred_at: at }
    end

    def cancel(_reserva, at:)
      { success: true, occurred_at: at }
    end

    def precheckin_status(reserva)
      {
        completed: reserva.fnrh_information_released?,
        statuses: []
      }
    end
  end
end
