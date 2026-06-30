require "test_helper"

class Public::CalendarControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 1, 1, 12)
  end

  teardown do
    travel_back
  end

  test "exports reservation end date as checkout DTEND" do
    filial = Filial.create!(name: "Filial teste")
    cabana = Cabana.create!(name: "Cabana teste", price: 100, filial: filial)
    user = User.create!(
      email: "hospede@example.com",
      password: "password",
      password_confirmation: "password",
      name: "Hospede"
    )
    Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 10),
      end_date: Date.new(2026, 6, 12),
      payment_status: "paid",
      total_price: 0
    )

    get public_calendar_export_path(cabana, format: :ics)

    assert_response :success

    calendar = Icalendar::Calendar.parse(response.body).first
    event = calendar.events.first

    assert_equal Date.new(2026, 6, 10), event.dtstart.to_date
    assert_equal Date.new(2026, 6, 12), event.dtend.to_date
  end

  test "exports the extra blocked nights for early check in and late checkout" do
    filial = Filial.create!(name: "Filial operacional")
    cabana = Cabana.create!(name: "Cabana operacional", price: 100, filial: filial)
    user = User.create!(
      email: "hospede-operacional@example.com",
      password: "password",
      password_confirmation: "password",
      name: "Hospede"
    )
    Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 7, 10),
      end_date: Date.new(2026, 7, 12),
      early_checkin: true,
      late_checkout: true,
      payment_status: "paid",
      total_price: 0
    )

    get public_calendar_export_path(cabana, format: :ics)

    event = Icalendar::Calendar.parse(response.body).first.events.first
    assert_equal Date.new(2026, 7, 9), event.dtstart.to_date
    assert_equal Date.new(2026, 7, 13), event.dtend.to_date
  end
end
