require "test_helper"

class ReservasControllerTest < ActionDispatch::IntegrationTest
  test "unavailable dates include operational block details" do
    filial = Filial.create!(name: "Filial calendário detalhado")
    cabana = Cabana.create!(name: "Cabana calendário detalhado", price: 100, filial: filial, color: "#336699")
    guest = User.create!(
      name: "Hóspede calendário",
      email: "calendar-details@example.com",
      password: "password",
      password_confirmation: "password"
    )
    Reserva.create!(
      cabana: cabana,
      user: guest,
      start_date: Date.new(2027, 8, 10),
      end_date: Date.new(2027, 8, 12),
      early_checkin: true,
      late_checkout: true,
      payment_status: "paid",
      blocks_availability: true,
      total_price: 0
    )

    get "/cabanas/#{cabana.id}/unavailable_dates", params: { details: true }

    assert_response :success
    payload = response.parsed_body
    assert_includes payload.fetch("disabled_dates"), "2027-08-09"
    assert_includes payload.fetch("disabled_dates"), "2027-08-12"
    assert_includes payload.fetch("operational_blocks"), {
      "date" => "2027-08-09",
      "type" => "early_checkin",
      "color" => "#336699"
    }
    assert_includes payload.fetch("operational_blocks"), {
      "date" => "2027-08-12",
      "type" => "late_checkout",
      "color" => "#336699"
    }
  end

  test "should get index" do
    get reservas_index_url
    assert_response :success
  end

  test "should get show" do
    get reservas_show_url
    assert_response :success
  end

  test "should get new" do
    get reservas_new_url
    assert_response :success
  end

  test "should get create" do
    get reservas_create_url
    assert_response :success
  end
end
