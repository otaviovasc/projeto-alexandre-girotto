require "test_helper"

class PriceCalculatorTest < ActiveSupport::TestCase
  test "does not charge required cleaning services" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    user = User.create!(
      email: "price@example.com",
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
    ["➡️ Limpeza Entrada (MG)", "⬅️ Limpeza de Saida (MG)"].each do |name|
      Service.create!(name: name, price: 500, filial: filial, user: user)
    end
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )

    assert_equal 200, PriceCalculator.new(reserva).total_price
  end

  test "does not charge breakfast included by cabana configuration" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(name: "Cabana SP", price: 100, filial: filial)
    user = User.create!(
      email: "included-breakfast-price@example.com",
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
    breakfast = Service.create!(name: "Café da Manhã", price: 80, filial: filial, user: user)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )
    reserva.reserva_services.create!(
      service: breakfast,
      quantity: 1,
      service_date: reserva.start_date,
      observation: BreakfastServicesAssigner::AUTO_OBSERVATION
    )

    assert_equal 200, PriceCalculator.new(reserva).total_price
  end

  test "charges manually added breakfast per service date" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(name: "Cabana SP", price: 100, filial: filial)
    user = User.create!(
      email: "manual-breakfast-price@example.com",
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
    breakfast = Service.create!(name: "Café da Manhã", price: 80, filial: filial, user: user)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 9),
      end_date: Date.new(2026, 6, 12),
      payment_status: "paid",
      total_price: 0
    )
    [Date.new(2026, 6, 10), Date.new(2026, 6, 11), Date.new(2026, 6, 12)].each do |service_date|
      reserva.reserva_services.create!(
        service: breakfast,
        quantity: 1,
        service_date: service_date
      )
    end

    assert_equal 540, PriceCalculator.new(reserva).total_price
  end
end
