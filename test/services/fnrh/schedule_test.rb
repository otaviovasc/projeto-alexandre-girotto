require 'test_helper'

module Fnrh
  class ScheduleTest < ActiveSupport::TestCase
    test 'uses 23:00 instead of producing an invalid 22:60 time' do
      reserva = Reserva.new(id: 7, start_date: Date.new(2026, 7, 2))

      scheduled_at = Schedule.checkin_at(reserva)

      assert_equal 23, scheduled_at.hour
      assert_equal 0, scheduled_at.min
    end
  end
end
