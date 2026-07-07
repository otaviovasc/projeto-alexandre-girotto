require "test_helper"

class ReservaServiceTest < ActiveSupport::TestCase
  test "rejects a new non cleaning service outside the official stay" do
    filial = Filial.create!(name: "Filial serviço", region: "MG")
    cabana = Cabana.create!(name: "Cabana serviço", price: 100, filial: filial)
    user = create_user("service-guest@example.com")
    service = Service.create!(name: "Jantar", price: 100, filial: filial, user: create_user("service-owner@example.com"))
    reserva = Reserva.new(
      cabana: cabana,
      user: user,
      start_date: Date.new(2027, 7, 10),
      end_date: Date.new(2027, 7, 12),
      payment_status: "paid",
      total_price: 0
    )

    reserva_service = ReservaService.new(
      reserva: reserva,
      service: service,
      quantity: 1,
      service_date: Date.new(2027, 7, 13)
    )

    assert_not reserva_service.valid?
    assert_includes reserva_service.errors[:service_date], "deve estar entre o check-in e o check-out da reserva."
  end

  test "allows a service containing cobrar on a date outside the stay" do
    filial = Filial.create!(name: "Filial cobrança", region: "MG")
    cabana = Cabana.create!(name: "Cabana cobrança", price: 100, filial: filial)
    service = Service.create!(
      name: "💰 Lembrete de cobrança da segunda parcela",
      price: 0,
      filial: filial,
      user: create_user("billing-owner@example.com")
    )
    reserva = Reserva.new(
      cabana: cabana,
      user: create_user("billing-guest@example.com"),
      start_date: Date.new(2027, 7, 10),
      end_date: Date.new(2027, 7, 12),
      payment_status: "paid",
      total_price: 0
    )
    reserva_service = ReservaService.new(
      reserva: reserva,
      service: service,
      quantity: 1,
      service_date: Date.new(2027, 6, 1)
    )

    assert reserva_service.valid?
  end

  private

  def create_user(email)
    User.create!(
      email: email,
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
  end
end
