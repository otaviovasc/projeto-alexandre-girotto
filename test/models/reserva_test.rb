require "test_helper"

class ReservaTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "service purchases close ten days before check in" do
    reserva = Reserva.new(start_date: Date.new(2026, 1, 26))

    assert_equal Date.new(2026, 1, 16), reserva.service_purchase_block_date

    travel_to Time.zone.local(2026, 1, 15, 12) do
      assert reserva.service_purchase_window_open?
    end

    travel_to Time.zone.local(2026, 1, 16, 12) do
      assert_not reserva.service_purchase_window_open?
    end

    travel_to Time.zone.local(2026, 1, 26, 12) do
      assert_not reserva.service_purchase_window_open?
    end
  end

  test "service purchase override stays open through check in" do
    reserva = Reserva.new(
      start_date: Date.new(2026, 1, 26),
      service_purchase_override: true
    )

    assert reserva.service_purchase_window_open?(Date.new(2026, 1, 20))
    assert reserva.service_purchase_window_open?(Date.new(2026, 1, 26))
    assert_not reserva.service_purchase_window_open?(Date.new(2026, 1, 27))
  end
end
