require "test_helper"

class ReservasHelperTest < ActionView::TestCase
  test "identifies early and late operational calendar segments" do
    reserva = Reserva.new(
      start_date: Date.new(2027, 8, 10),
      end_date: Date.new(2027, 8, 12),
      early_checkin: true,
      late_checkout: true
    )

    early_segments = calendar_reservation_segments(reserva, reserva.start_date)
    late_segments = calendar_reservation_segments(reserva, reserva.end_date)

    assert_includes early_segments, { css_class: "end", operational: true, operational_type: "early-checkin" }
    assert_includes late_segments, { css_class: "start", operational: true, operational_type: "late-checkout" }
    assert early_segments.any? { |segment| !segment[:operational] && segment[:joins_operational] }
    assert late_segments.any? { |segment| !segment[:operational] && segment[:joins_operational] }
  end
end
