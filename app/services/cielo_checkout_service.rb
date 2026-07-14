require "base64"
require "bigdecimal"
require "httparty"

class CieloCheckoutService
  ORDERS_API_URL = "https://cieloecommerce.cielo.com.br/api/public/v1/orders".freeze
  TOKEN_API_URL = "https://cieloecommerce.cielo.com.br/api/public/v2/token".freeze
  TRANSACTIONS_API_URL = "https://cieloecommerce.cielo.com.br/api/public/v2".freeze
  REQUEST_TIMEOUT_SECONDS = 30

  class Error < StandardError
    attr_reader :response

    def initialize(message, response = nil)
      super(message)
      @response = response
    end
  end

  def initialize(merchant_id:, order_code:, items:, return_url:, customer: {}, soft_descriptor: "VILLAGGIO", max_installments: 1)
    @merchant_id = merchant_id.to_s.strip
    @order_code = normalize_order_code(order_code)
    @items = items
    @return_url = return_url
    @customer = customer || {}
    @soft_descriptor = soft_descriptor.to_s.strip.presence || "VILLAGGIO"
    @max_installments = max_installments.to_i.clamp(1, 12)
  end

  def call
    raise Error, "MerchantId da Cielo nao configurado para esta filial." if @merchant_id.blank?
    raise Error, "Carrinho vazio." if @items.blank?

    response = HTTParty.post(
      ORDERS_API_URL,
      headers: create_order_headers,
      body: payload.to_json,
      timeout: REQUEST_TIMEOUT_SECONDS
    )
    parsed_response = parse_response(response)
    checkout_url = checkout_url_from(parsed_response, response)

    unless response.code.between?(200, 299) && checkout_url.present?
      error_message = parsed_response["message"] || parsed_response["Message"] || response.message
      raise Error.new("Erro ao criar checkout Cielo: #{error_message}", response)
    end

    {
      "id" => @order_code,
      "url" => checkout_url,
      "provider" => ServicePaymentProvider::CIELO_CHECKOUT,
      "raw" => parsed_response
    }
  end

  def payload
    body = {
      OrderNumber: @order_code,
      SoftDescriptor: @soft_descriptor.first(13),
      Cart: {
        Items: normalized_items
      },
      Shipping: {
        Type: "WithoutShipping"
      },
      Payment: {
        MaxNumberOfInstallments: @max_installments
      },
      Options: {
        ReturnUrl: @return_url
      }
    }

    body[:Customer] = normalized_customer if normalized_customer.present?
    body
  end

  class TransactionQuery
    def initialize(client_id:, client_secret:)
      @client_id = client_id.to_s.strip
      @client_secret = client_secret.to_s.strip
    end

    def find_by_checkout_order_number(checkout_order_number)
      return {} if checkout_order_number.blank?

      response = HTTParty.get(
        "#{TRANSACTIONS_API_URL}/orders/#{checkout_order_number}",
        headers: {
          "Authorization" => "Bearer #{access_token}",
          "Accept" => "application/json"
        },
        timeout: REQUEST_TIMEOUT_SECONDS
      )

      parsed_response = parse_response(response)
      return parsed_response if response.code.between?(200, 299)

      raise Error.new("Erro ao consultar pagamento Cielo: #{parsed_response['message'] || response.message}", response)
    end

    private

    def access_token
      raise Error, "ClientId da Cielo nao configurado." if @client_id.blank?
      raise Error, "ClientSecret da Cielo nao configurado." if @client_secret.blank?

      credentials = Base64.strict_encode64("#{@client_id}:#{@client_secret}")
      response = HTTParty.post(
        TOKEN_API_URL,
        headers: {
          "Authorization" => "Basic #{credentials}",
          "Content-Type" => "application/x-www-form-urlencoded",
          "Accept" => "application/json"
        },
        body: "grant_type=client_credentials",
        timeout: REQUEST_TIMEOUT_SECONDS
      )
      parsed_response = parse_response(response)
      token = parsed_response["access_token"]

      return token if response.code.between?(200, 299) && token.present?

      raise Error.new("Erro ao autenticar na Cielo: #{parsed_response['message'] || response.message}", response)
    end

    def parse_response(response)
      JSON.parse(response.body.presence || "{}")
    rescue JSON::ParserError
      {}
    end
  end

  private

  def create_order_headers
    {
      "MerchantId" => @merchant_id,
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  def normalized_items
    @items.map.with_index do |item, index|
      {
        Name: item.fetch(:name).to_s.first(128),
        Description: item.fetch(:description, item.fetch(:name)).to_s.first(256),
        UnitPrice: to_cents(item.fetch(:unit_price)),
        Quantity: item.fetch(:quantity).to_i,
        Type: "Service",
        Sku: item.fetch(:id, index + 1).to_s.gsub(/[^A-Za-z0-9]/, "").first(32)
      }.compact
    end
  end

  def normalized_customer
    {
      FullName: @customer[:name].to_s.first(288).presence,
      Email: @customer[:email].to_s.first(64).presence,
      Phone: @customer[:phone].to_s.gsub(/\D/, "").first(11).presence
    }.compact
  end

  def normalize_order_code(value)
    normalized = value.to_s.gsub(/[^A-Za-z0-9]/, "")
    normalized = "SV#{Time.current.to_i}" if normalized.blank?
    normalized.first(20)
  end

  def to_cents(value)
    (BigDecimal(value.to_s) * 100).round.to_i
  end

  def parse_response(response)
    JSON.parse(response.body.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def checkout_url_from(response_body, response = nil)
    url_from_body = if response_body.is_a?(Hash)
                      response_body.dig("Settings", "CheckoutUrl").presence ||
                        response_body.dig("settings", "checkoutUrl").presence ||
                        response_body.dig("settings", "CheckoutUrl").presence ||
                        response_body.dig("Settings", "checkoutUrl").presence ||
                        find_checkout_url(response_body)
                    end

    url_from_body.presence || checkout_url_from_headers(response)
  end

  def checkout_url_from_headers(response)
    return unless response.respond_to?(:headers)

    response.headers["location"].presence ||
      response.headers["Location"].presence ||
      response.headers["checkouturl"].presence ||
      response.headers["CheckoutUrl"].presence
  end

  def find_checkout_url(value)
    case value
    when Hash
      value.each do |key, nested_value|
        if key.to_s.downcase.include?("checkout") && nested_value.to_s.match?(%r{\Ahttps?://})
          return nested_value.to_s
        end

        found = find_checkout_url(nested_value)
        return found if found.present?
      end
    when Array
      value.each do |nested_value|
        found = find_checkout_url(nested_value)
        return found if found.present?
      end
    when String
      return value if value.include?("cieloecommerce.cielo.com.br/transacional/order")
    end
  end
end
