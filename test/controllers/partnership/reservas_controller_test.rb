require "test_helper"

class Partnership::ReservasControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @agent = User.create!(
      name: "Milena Teste",
      email: "milena-test@example.com",
      password: "password",
      password_confirmation: "password",
      role: :partnership_agent
    )
    guest = User.create!(
      name: "Hóspede Parceiro",
      email: "partner-guest@example.com",
      password: "password",
      password_confirmation: "password",
      partner: true
    )
    filial = Filial.create!(name: "Filial parceria")
    cabana = Cabana.create!(name: "Cabana parceria", price: 100, filial: filial)
    @new_cabana = Cabana.create!(name: "Nova cabana parceria", price: 150, filial: filial)
    @reserva = Reserva.create!(
      cabana: cabana,
      user: guest,
      partnership_creator: @agent,
      start_date: Date.new(2027, 8, 10),
      end_date: Date.new(2027, 8, 12),
      payment_status: "paid",
      total_price: 0,
      observation: "Parceria"
    )
    sign_in @agent
  end

  test "partnership agent can update partnership dates only" do
    patch partnership_reserva_path(@reserva), params: {
      reserva: {
        start_date: "2027-09-15",
        end_date: "2027-09-17",
        cabana_id: @new_cabana.id,
        total_price: 99_999
      }
    }

    assert_redirected_to partnership_dashboard_path(
      start_date: Date.new(2027, 9, 1),
      anchor: "calendario-parcerias"
    )
    @reserva.reload
    assert_equal Date.new(2027, 9, 15), @reserva.start_date
    assert_equal Date.new(2027, 9, 17), @reserva.end_date
    assert_equal @new_cabana, @reserva.cabana
    assert_equal 0, @reserva.total_price
  end
end
