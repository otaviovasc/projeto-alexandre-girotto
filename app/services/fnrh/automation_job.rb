module Fnrh
  class AutomationJob
    def self.run(now: Time.current)
      new(now: now).run
    end

    def initialize(now:)
      @now = now
    end

    def run
      run_reservation_syncs
      run_precheckin_status_syncs
      run_cancellations
      run_expired_precheckin_no_shows
      run_checkins
      run_checkouts
    end

    private

    def run_reservation_syncs
      Reserva.where(fnrh_reservation_id: nil, payment_status: 'paid', group_created: true)
             .where.not(fnrh_status: %w[error precheckin_bypassed duplicate_in_fnrh])
             .where('end_date >= ?', Date.current)
             .find_each do |reserva|
        ReservationSyncService.new(reserva, source: 'automatic').call(force: true)
      rescue => e
        Rails.logger.error("Erro na sincronização automática FNRH da reserva ##{reserva.id}: #{e.message}")
      end
    end

    def run_cancellations
      Reserva.where(payment_status: 'canceled')
             .where.not(fnrh_reservation_id: nil)
             .where.not(fnrh_status: 'cancelled')
             .find_each do |reserva|
        TransitionService.new(reserva, source: 'automatic').cancel(at: @now)
      rescue => e
        Rails.logger.error("Erro no cancelamento automático FNRH da reserva ##{reserva.id}: #{e.message}")
      end
    end

    def run_precheckin_status_syncs
      Reserva.where(fnrh_status: 'awaiting_precheckin')
             .where.not(fnrh_reservation_id: nil)
             .find_each do |reserva|
        PrecheckinStatusSyncService.new(reserva, source: 'automatic').call
      rescue => e
        Rails.logger.error("Erro na consulta de pré-check-in FNRH da reserva ##{reserva.id}: #{e.message}")
      end
    end

    def run_checkins
      Reserva.where(fnrh_status: 'precheckin_completed')
             .where('fnrh_scheduled_checkin_at <= ?', @now)
             .find_each do |reserva|
        TransitionService.new(reserva, source: 'automatic').check_in(at: @now)
      rescue => e
        Rails.logger.error("Erro no check-in automático FNRH da reserva ##{reserva.id}: #{e.message}")
      end
    end

    def run_expired_precheckin_no_shows
      Reserva.where(fnrh_status: 'awaiting_precheckin')
             .where.not(fnrh_reservation_id: nil)
             .where('end_date <= ?', @now.to_date)
             .find_each do |reserva|
        next if Schedule.checkout_at(reserva) > @now

        TransitionService.new(reserva, source: 'automatic').no_show(at: @now)
      rescue => e
        Rails.logger.error("Erro no no-show automático FNRH da reserva ##{reserva.id}: #{e.message}")
      end
    end

    def run_checkouts
      Reserva.where(fnrh_status: 'checked_in').find_each do |reserva|
        next if Schedule.checkout_at(reserva) > @now

        TransitionService.new(reserva, source: 'automatic').check_out(at: @now)
      rescue => e
        Rails.logger.error("Erro no checkout automático FNRH da reserva ##{reserva.id}: #{e.message}")
      end
    end
  end
end
