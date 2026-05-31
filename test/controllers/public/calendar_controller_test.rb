require "test_helper"

class Public::CalendarControllerTest < ActionDispatch::IntegrationTest
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
end
