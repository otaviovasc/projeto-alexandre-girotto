require "test_helper"

class ServicePurchaseDatePolicyTest < ActiveSupport::TestCase
  test "blocks service dates from december 24 to january 2" do
    assert ServicePurchaseDatePolicy.blocked_holiday_service_date?(Date.new(2026, 12, 24))
    assert ServicePurchaseDatePolicy.blocked_holiday_service_date?(Date.new(2027, 1, 2))
    assert_not ServicePurchaseDatePolicy.blocked_holiday_service_date?(Date.new(2026, 12, 23))
    assert_not ServicePurchaseDatePolicy.blocked_holiday_service_date?(Date.new(2027, 1, 3))
  end

  test "detects stays that touch blocked holiday period" do
    assert ServicePurchaseDatePolicy.blocked_holiday_period?(Date.new(2026, 12, 23), Date.new(2026, 12, 25))
    assert ServicePurchaseDatePolicy.blocked_holiday_period?(Date.new(2026, 12, 31), Date.new(2027, 1, 3))
    assert_not ServicePurchaseDatePolicy.blocked_holiday_period?(Date.new(2026, 12, 20), Date.new(2026, 12, 23))
    assert_not ServicePurchaseDatePolicy.blocked_holiday_period?(Date.new(2027, 1, 3), Date.new(2027, 1, 5))
  end

  test "blocks september 2026 service dates only for Serra da Mantiqueira" do
    serra = Filial.new(name: "Serra da Mantiqueira")
    brauna = Filial.new(name: "Fattoria di Brauna")

    assert ServicePurchaseDatePolicy.blocked_service_date?(Date.new(2026, 9, 16), filial: serra)
    assert ServicePurchaseDatePolicy.blocked_service_date?(Date.new(2026, 9, 19), filial: serra)
    assert_not ServicePurchaseDatePolicy.blocked_service_date?(Date.new(2026, 9, 15), filial: serra)
    assert_not ServicePurchaseDatePolicy.blocked_service_date?(Date.new(2026, 9, 20), filial: serra)
    assert_not ServicePurchaseDatePolicy.blocked_service_date?(Date.new(2026, 9, 16), filial: brauna)
  end

  test "detects Serra da Mantiqueira blocked service period from reservation" do
    filial = Filial.new(name: "Serra da Mantiqueira")
    cabana = Cabana.new(name: "Cabana Serra", filial: filial)
    reserva = Reserva.new(cabana: cabana)

    assert ServicePurchaseDatePolicy.blocked_service_period?(
      Date.new(2026, 9, 15),
      Date.new(2026, 9, 17),
      reserva: reserva
    )
  end
end
