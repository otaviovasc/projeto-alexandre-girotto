class ServicePaymentProvider
  CIELO_CHECKOUT = "cielo_checkout".freeze
  PAGARME = "pagarme".freeze

  class << self
    def current
      configured = ENV.fetch("SERVICE_PAYMENT_PROVIDER", PAGARME).to_s.strip.downcase
      configured == CIELO_CHECKOUT ? CIELO_CHECKOUT : PAGARME
    end

    def cielo_checkout?
      current == CIELO_CHECKOUT
    end
  end
end
