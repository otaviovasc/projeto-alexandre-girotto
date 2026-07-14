require "test_helper"

class CieloCheckoutServiceTest < ActiveSupport::TestCase
  test "creates checkout with merchant id header and service payload" do
    calls = []
    response = Struct.new(:code, :body, :message).new(
      200,
      { Settings: { CheckoutUrl: "https://cieloecommerce.cielo.com.br/transacional/order/index?id=123" } }.to_json,
      "OK"
    )

    post_stub = lambda do |_url, headers:, body:, timeout:|
      calls << {
        headers: headers,
        body: JSON.parse(body),
        timeout: timeout
      }
      response
    end

    HTTParty.stub(:post, post_stub) do
      result = CieloCheckoutService.new(
        merchant_id: "da84afda-8edf-4d2b-9089-4ba1dd47a5ba",
        order_code: "PS6141720960000",
        items: [{ id: 1, name: "Almoco", unit_price: 65, quantity: 2 }],
        return_url: "https://example.com/minha-reserva/confirmacao",
        customer: { name: "Romulo", email: "romulo@example.com", phone: "(11) 99999-8888" },
        max_installments: 3
      ).call

      assert_equal "123", result["id"]
      assert_equal "https://cieloecommerce.cielo.com.br/transacional/order/index?id=123", result["url"]
    end

    payload = calls.first[:body]

    assert_equal "da84afda-8edf-4d2b-9089-4ba1dd47a5ba", calls.first[:headers]["MerchantId"]
    assert_equal "PS6141720960000", payload["OrderNumber"]
    assert_equal "VILLAGGIO", payload["SoftDescriptor"]
    assert_equal "WithoutShipping", payload.dig("Shipping", "Type")
    assert_equal 3, payload.dig("Payment", "MaxNumberOfInstallments")
    assert_equal 6500, payload.dig("Cart", "Items", 0, "UnitPrice")
    assert_equal "Service", payload.dig("Cart", "Items", 0, "Type")
    assert_equal "11999998888", payload.dig("Customer", "Phone")
  end

  test "uses configured merchant ids for known filials" do
    assert_equal "da84afda-8edf-4d2b-9089-4ba1dd47a5ba",
                 Filial.new(name: "Serra da Mantiqueira").cielo_checkout_merchant_id_for_payments
    assert_equal "48ec393d-e6cd-4734-8b68-1c307ed949ac",
                 Filial.new(name: "Fattoria di Brauna").cielo_checkout_merchant_id_for_payments
  end

  test "accepts lowercase checkout url response from Cielo" do
    service = CieloCheckoutService.new(
      merchant_id: "da84afda-8edf-4d2b-9089-4ba1dd47a5ba",
      order_code: "PS6141720960000",
      items: [{ id: 1, name: "Almoco", unit_price: 65, quantity: 1 }],
      return_url: "https://example.com/minha-reserva/confirmacao"
    )

    response_body = {
      "settings" => {
        "checkoutUrl" => "https://cieloecommerce.cielo.com.br/transacional/order/index?id=abc"
      }
    }

    assert_equal "https://cieloecommerce.cielo.com.br/transacional/order/index?id=abc",
                 service.send(:checkout_url_from, response_body)
  end

  test "accepts checkout url from response location header" do
    service = CieloCheckoutService.new(
      merchant_id: "da84afda-8edf-4d2b-9089-4ba1dd47a5ba",
      order_code: "PS6141720960000",
      items: [{ id: 1, name: "Almoco", unit_price: 65, quantity: 1 }],
      return_url: "https://example.com/minha-reserva/confirmacao"
    )
    response = Struct.new(:headers).new(
      { "location" => "https://cieloecommerce.cielo.com.br/transacional/order/index?id=def" }
    )

    assert_equal "https://cieloecommerce.cielo.com.br/transacional/order/index?id=def",
                 service.send(:checkout_url_from, {}, response)
  end

  test "reads paid status from different Cielo response formats" do
    assert_equal "paid", CieloCheckoutService.payment_status_from_transaction(
      { "payment" => { "status" => 2 } }
    )
    assert_equal "paid", CieloCheckoutService.payment_status_from_transaction(
      { "Payment" => { "Status" => "Pago" } }
    )
    assert_equal "paid", CieloCheckoutService.payment_status_from_transaction(
      { "paymentStatus" => "paid" }
    )
  end
end
