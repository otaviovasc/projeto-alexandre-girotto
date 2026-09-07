require "test_helper"

class ServicePurchaseLateFeeCartTest < ActiveSupport::TestCase
  test "adds automatic late fee cart item when purchase is outside deadline" do
    reserva = reservas(:one)
    reserva.update_columns(
      start_date: Date.current + 5.days,
      end_date: Date.current + 7.days,
      service_purchase_override: true,
      service_purchase_override_until: Date.current + 7.days,
      service_purchase_late_fee_waived: false
    )
    cart = reserva.user.cart || reserva.user.create_cart
    cart.cart_items.destroy_all

    CartItem.create!(
      cart: cart,
      reserva: reserva,
      service: services(:one),
      quantity: 1,
      service_date: reserva.start_date + 1.day
    )

    ServicePurchaseLateFeeCart.sync!(reserva: reserva, cart: cart)

    fee_item = cart.cart_items.includes(:service).detect do |cart_item|
      ServicePurchaseLateFeeCart.late_fee_cart_item?(cart_item)
    end

    assert fee_item
    assert_nil fee_item.service_date
    assert_equal Service::SERVICE_PURCHASE_LATE_FEE_NAME, fee_item.service.name
    assert_equal BigDecimal("50"), fee_item.service.price
    assert_not fee_item.service.show_in_marketplace?
  end

  test "removes editable late fee cart item when fee is waived" do
    reserva = reservas(:one)
    reserva.update_columns(
      start_date: Date.current + 5.days,
      end_date: Date.current + 7.days,
      service_purchase_override: true,
      service_purchase_override_until: Date.current + 7.days,
      service_purchase_late_fee_waived: false
    )
    cart = reserva.user.cart || reserva.user.create_cart
    cart.cart_items.destroy_all

    CartItem.create!(
      cart: cart,
      reserva: reserva,
      service: services(:one),
      quantity: 1,
      service_date: reserva.start_date + 1.day
    )
    ServicePurchaseLateFeeCart.sync!(reserva: reserva, cart: cart)

    reserva.update_columns(service_purchase_late_fee_waived: true)
    ServicePurchaseLateFeeCart.sync!(reserva: reserva.reload, cart: cart)

    assert_not cart.cart_items.includes(:service).any? { |cart_item| ServicePurchaseLateFeeCart.late_fee_cart_item?(cart_item) }
  end
end
