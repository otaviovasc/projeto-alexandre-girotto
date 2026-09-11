require "test_helper"

class PartnershipDiscountCouponTest < ActiveSupport::TestCase
  test "normalizes code ignoring case and spaces" do
    assert_equal "CLAU20", PartnershipDiscountCoupon.normalize_code(" Clau 20 ")
  end

  test "calculates discount amount" do
    coupon = PartnershipDiscountCoupon.new(code: "CLAU20", discount_percent: 20)

    assert_equal BigDecimal("40.0"), coupon.discount_amount_for(200)
  end
end
