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
end
