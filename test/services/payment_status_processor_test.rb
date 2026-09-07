require "test_helper"

class PaymentStatusProcessorTest < ActiveSupport::TestCase
  test "does not reactivate replaced checkout when Cielo sends waiting status" do
    order_code = "PSREPLACEDWAIT"
    cart_item = CartItem.create!(
      cart: carts(:one),
      reserva: reservas(:one),
      service: services(:one),
      quantity: 1,
      service_date: reservas(:one).start_date,
      payment_status: "checkout_replaced",
      payment_order_code: order_code,
      unit_price_paid: 10.00,
      total_paid: 10.00
    )

    PaymentStatusProcessor.call(identifiers: [order_code], status: "waiting_payment")

    assert_equal "checkout_replaced", cart_item.reload.payment_status
  end

  test "confirms replaced checkout if old Cielo link is paid" do
    order_code = "PSREPLACEDPAID"
    cart_item = CartItem.create!(
      cart: carts(:one),
      reserva: reservas(:one),
      service: services(:one),
      quantity: 1,
      service_date: reservas(:one).start_date,
      payment_status: "checkout_replaced",
      payment_order_code: order_code,
      unit_price_paid: 10.00,
      total_paid: 10.00
    )

    PaymentStatusProcessor.call(identifiers: [order_code], status: "paid")

    assert_nil CartItem.find_by(id: cart_item.id)
    service_purchase = ReservaService.find_by!(payment_order_code: order_code)
    assert_equal "paid", service_purchase.payment_status
    assert_equal BigDecimal("10.0"), service_purchase.total_paid
  end
end
