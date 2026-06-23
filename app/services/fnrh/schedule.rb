module Fnrh
  class Schedule
    class << self
      def checkin_at(reserva)
        offset_minutes = 31 + ((reserva.id.to_i * 17) % 30)
        local_time(reserva.start_date, hour: 22, minute: 0) + offset_minutes.minutes
      end

      def checkout_at(reserva)
        hour, minute = Configuration.checkout_time.split(':').map(&:to_i)
        local_time(reserva.end_date, hour: hour, minute: minute)
      end

      private

      def local_time(date, hour:, minute:)
        Time.zone.local(date.year, date.month, date.day, hour, minute)
      end
    end
  end
end
