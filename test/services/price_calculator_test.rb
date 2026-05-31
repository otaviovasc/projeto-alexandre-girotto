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
end
