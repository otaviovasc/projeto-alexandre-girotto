require 'base64'
require 'bigdecimal'
require 'httparty'

class PagarmePaymentLinkService
  PRODUCTION_API_URL = 'https://api.pagar.me/core/v5/paymentlinks'.freeze
  SANDBOX_API_URL = 'https://sdx-api.pagar.me/core/v5/paymentlinks'.freeze
  REQUEST_TIMEOUT_SECONDS = 10

  class Error < StandardError
    attr_reader :response

    def initialize(message, response = nil)
      super(message)
      @response = response
    end
  end

  def initialize(api_key:, name:, order_code:, items:, success_url:, failure_url: success_url, expires_in: 30)
    @api_key = api_key.to_s.strip
    @name = name
    @order_code = order_code
    @items = items
    @success_url = success_url
    @failure_url = failure_url
    @expires_in = expires_in
  end

  def call
    raise Error, 'Chave da Pagar.me nao configurada para esta filial.' if @api_key.blank?
    raise Error, 'Carrinho vazio.' if @items.blank?

    response = post_payment_link
    parsed_response = parse_response(response)

    unless response.code.between?(200, 299) && parsed_response['url'].present?
      error_message = parsed_response['errors'] || parsed_response['message'] || response.message
      raise Error.new("Erro ao criar link de pagamento: #{error_message}", response)
    end

    parsed_response
  end

  private

  def post_payment_link
    response = HTTParty.post(api_url, headers: headers, body: payload.to_json, timeout: REQUEST_TIMEOUT_SECONDS)
    return response unless response.code == 401

    HTTParty.post(api_url, headers: headers(password: 'x'), body: payload.to_json, timeout: REQUEST_TIMEOUT_SECONDS)
  end

  def api_url
    return SANDBOX_API_URL if @api_key.start_with?('sk_test')

    PRODUCTION_API_URL
  end

  def headers(password: '')
    credentials = Base64.strict_encode64("#{@api_key}:#{password}")

    {
      'Authorization' => "Basic #{credentials}",
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def payload
    amount_in_cents = normalized_items.sum { |item| item[:amount] * item[:default_quantity] }
    expires_in_seconds = @expires_in.to_i * 60

    {
      is_building: false,
      type: 'order',
      name: @name.to_s.first(64),
      order_code: @order_code,
      expires_in: expires_in_seconds,
      max_paid_sessions: 1,
      payment_settings: {
        credit_card_settings: {
          installments_setup: {
            interest_type: 'simple',
            interest_rate: 0,
            max_installments: 1,
            amount: amount_in_cents
          },
          operation_type: 'auth_and_capture'
        },
        pix_settings: {
          expires_in: expires_in_seconds
        },
        accepted_payment_methods: [
          'credit_card',
          'pix'
        ]
      },
      cart_settings: {
        items: normalized_items
      },
      success_url: @success_url,
      failure_url: @failure_url
    }
  end

  def normalized_items
    @normalized_items ||= @items.map.with_index do |item, index|
      unit_price = to_cents(item.fetch(:unit_price))
      quantity = item.fetch(:quantity).to_i

      {
        id: item.fetch(:id, index + 1).to_s,
        name: item.fetch(:name).to_s.first(64),
        amount: unit_price,
        unit_price: unit_price,
        default_quantity: quantity
      }
    end
  end

  def to_cents(value)
    (BigDecimal(value.to_s) * 100).round.to_i
  end

  def parse_response(response)
    JSON.parse(response.body.presence || '{}')
  rescue JSON::ParserError
    {}
  end
end
