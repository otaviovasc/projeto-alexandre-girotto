require "test_helper"

class PagarmePaymentLinkServiceTest < ActiveSupport::TestCase
  test "sends link expiration to Pagarme in seconds" do
    calls = []
    response = Struct.new(:code, :body, :message).new(
      200,
      { id: "plink_test", url: "https://payment-link-v3.pagar.me/test" }.to_json,
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
      PagarmePaymentLinkService.new(
        api_key: "sk_test_123",
        name: "Servicos Reserva 614",
        order_code: "portal-services-614",
        items: [
          {
            id: 1,
            name: "Almoco",
            unit_price: 100,
            quantity: 1
          }
        ],
        success_url: "https://example.com/success",
        expires_in: 10
      ).call
    end

    payload = calls.first[:body]

    assert_equal 600, payload["expires_in"]
    assert_equal 600, payload.dig("payment_settings", "pix_settings", "expires_in")
    assert_equal 1, payload.dig("payment_settings", "credit_card_settings", "installments_setup", "max_installments")
  end

  test "allows a custom installment limit for service purchases" do
    service = PagarmePaymentLinkService.new(
      api_key: "sk_test_123",
      name: "Servicos Reserva 614",
      order_code: "portal-services-614",
      items: [{ id: 1, name: "Almoco", unit_price: 100, quantity: 1 }],
      success_url: "https://example.com/success",
      max_installments: 6
    )

    payload = service.send(:payload)

    assert_equal 6, payload.dig(:payment_settings, :credit_card_settings, :installments_setup, :max_installments)
  end
end
