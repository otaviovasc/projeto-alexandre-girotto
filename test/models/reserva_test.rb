require "test_helper"

class ReservaTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "service purchases close seven days before check in" do
    reserva = Reserva.new(start_date: Date.new(2026, 1, 26))

    assert_equal Date.new(2026, 1, 19), reserva.service_purchase_block_date

    travel_to Time.zone.local(2026, 1, 18, 12) do
      assert reserva.service_purchase_window_open?
    end

    travel_to Time.zone.local(2026, 1, 19, 12) do
      assert_not reserva.service_purchase_window_open?
    end

    travel_to Time.zone.local(2026, 1, 26, 12) do
      assert_not reserva.service_purchase_window_open?
    end
  end
end
