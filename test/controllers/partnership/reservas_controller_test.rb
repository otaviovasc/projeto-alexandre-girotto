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

  test "partnership agent can update all reservation details" do
    patch partnership_reserva_path(@reserva), params: {
      reserva: {
        start_date: "2027-09-15",
        end_date: "2027-09-17",
        cabana_id: @new_cabana.id,
        user_id: @reserva.user_id,
        total_price: 1_250,
        early_checkin: true,
        late_checkout: true,
        observation: "Parceria ajustada"
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
    assert_equal 1_250, @reserva.total_price
    assert @reserva.early_checkin?
    assert @reserva.late_checkout?
    assert_equal "Parceria ajustada", @reserva.observation
  end

  test "partnership agent can confirm a pending partnership" do
    @reserva.update_columns(payment_status: "pending", blocks_availability: false)

    patch confirm_reservation_partnership_reserva_path(@reserva)

    assert_redirected_to partnership_dashboard_path
    @reserva.reload
    assert @reserva.paid?
    assert @reserva.blocks_availability?
  end

  test "partnership agent cannot edit a regular reservation" do
    regular_guest = User.create!(
      name: "Hóspede comum",
      email: "regular-guest@example.com",
      password: "password",
      password_confirmation: "password"
    )
    regular = Reserva.create!(
      cabana: @new_cabana,
      user: regular_guest,
      start_date: Date.new(2028, 1, 10),
      end_date: Date.new(2028, 1, 12),
      payment_status: "paid",
      total_price: 500,
      observation: "Sistema"
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      get edit_partnership_reserva_path(regular)
    end
  end

  test "partnership routes do not allow deletion" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/parcerias/reservas/#{@reserva.id}",
        method: :delete
      )
    end
  end
end
