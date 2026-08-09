require "test_helper"

class PagamentosControllerTest < ActionDispatch::IntegrationTest
  test "accepts Cielo checkout notification by local order and amount match" do
    order_code = "PS8931784045954"
    cart_item = CartItem.create!(
      cart: carts(:one),
      reserva: reservas(:one),
      service: services(:one),
      quantity: 2,
      service_date: reservas(:one).start_date,
      payment_status: "waiting_payment",
      payment_order_code: order_code,
      unit_price_paid: 1.50,
      total_paid: 3.00
    )
    failing_query = Object.new
    failing_query.define_singleton_method(:find_by_order_number) do |_order_number|
      raise CieloCheckoutService::Error, "Not Found"
    end
    failing_query.define_singleton_method(:find_by_checkout_order_number) do |_checkout_order_number|
      raise CieloCheckoutService::Error, "Not Found"
    end

    CieloCheckoutService::TransactionQuery.stub(:new, failing_query) do
      post cielo_checkout_webhook_path, params: {
        order_number: order_code,
        checkout_cielo_order_number: "13b82aa998c94d1ebd07",
        amount: "300",
        payment_status: "2"
      }
    end

    assert_response :ok
    assert_nil CartItem.find_by(id: cart_item.id)

    service_purchase = ReservaService.find_by!(payment_order_code: order_code)
    assert_equal "paid", service_purchase.payment_status
    assert_equal "13b82aa998c94d1ebd07", service_purchase.payment_link_id
  end

  test "rejects Cielo checkout notification when local amount does not match" do
    order_code = "PS8931784045999"
    cart_item = CartItem.create!(
      cart: carts(:one),
      reserva: reservas(:one),
      service: services(:one),
      quantity: 2,
      service_date: reservas(:one).start_date,
      payment_status: "waiting_payment",
      payment_order_code: order_code,
      unit_price_paid: 1.50,
      total_paid: 3.00
    )
    failing_query = Object.new
    failing_query.define_singleton_method(:find_by_order_number) do |_order_number|
      raise CieloCheckoutService::Error, "Not Found"
    end
    failing_query.define_singleton_method(:find_by_checkout_order_number) do |_checkout_order_number|
      raise CieloCheckoutService::Error, "Not Found"
    end

    CieloCheckoutService::TransactionQuery.stub(:new, failing_query) do
      post cielo_checkout_webhook_path, params: {
        order_number: order_code,
        checkout_cielo_order_number: "13b82aa998c94d1ebd07",
        amount: "999",
        payment_status: "2"
      }
    end

    assert_response :unauthorized
    assert_equal "waiting_payment", cart_item.reload.payment_status
  end

  test "accepts Cielo checkout notification when service amount includes late fee" do
    order_code = "PS8931784045FEE"
    cart_item = CartItem.create!(
      cart: carts(:one),
      reserva: reservas(:one),
      service: services(:one),
      quantity: 2,
      service_date: reservas(:one).start_date,
      payment_status: "waiting_payment",
      payment_order_code: order_code,
      unit_price_paid: 1.50,
      total_paid: 3.00,
      service_late_fee_amount: 50.00
    )
    failing_query = Object.new
    failing_query.define_singleton_method(:find_by_order_number) do |_order_number|
      raise CieloCheckoutService::Error, "Not Found"
    end
    failing_query.define_singleton_method(:find_by_checkout_order_number) do |_checkout_order_number|
      raise CieloCheckoutService::Error, "Not Found"
    end

    CieloCheckoutService::TransactionQuery.stub(:new, failing_query) do
      post cielo_checkout_webhook_path, params: {
        order_number: order_code,
        checkout_cielo_order_number: "13b82aa998c94d1ebd07",
        amount: "5300",
        payment_status: "2"
      }
    end

    assert_response :ok
    assert_nil CartItem.find_by(id: cart_item.id)

    service_purchase = ReservaService.find_by!(payment_order_code: order_code)
    assert_equal "paid", service_purchase.payment_status
    assert_equal BigDecimal("50.0"), service_purchase.service_late_fee_amount
  end
end
