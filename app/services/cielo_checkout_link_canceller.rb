class CieloCheckoutLinkCanceller
  def self.call(reserva_payment:, source: 'system')
    new(reserva_payment: reserva_payment, source: source).call
  end

  def initialize(reserva_payment:, source: 'system')
    @reserva_payment = reserva_payment
    @source = source
  end

  def call
    return false unless ServicePaymentProvider.cielo_checkout?
    return false if @reserva_payment.blank? || @reserva_payment.payment_order_code.blank?

    filial = @reserva_payment.reserva&.cabana&.filial
    return false if filial.blank?

    transaction, lookup_source = transaction_query(filial).find_by_best_identifier(
      order_number: @reserva_payment.payment_order_code,
      checkout_order_number: checkout_order_number
    )

    status = CieloCheckoutService.payment_status_from_transaction(transaction)
    found_checkout_order_number = transaction['checkoutOrderNumber'].presence ||
                                  transaction['checkout_order_number'].presence ||
                                  checkout_order_number

    remember_checkout_order_number(found_checkout_order_number)

    if status == 'paid'
      Rails.logger.warn(
        "Checkout Cielo #{@reserva_payment.payment_order_code} ja estava pago ao tentar cancelar " \
        "(consulta=#{lookup_source}, source=#{@source})."
      )
      ReservaPaymentProcessor.call(reserva_payment: @reserva_payment.reload, status: 'paid', source: 'cielo_cancel_guard')
      return false
    end

    transaction_query(filial).void_checkout_order(found_checkout_order_number)
    Rails.logger.info(
      "Checkout Cielo #{@reserva_payment.payment_order_code} cancelado " \
      "checkout=#{found_checkout_order_number.presence || '-'} source=#{@source}."
    )
    true
  rescue CieloCheckoutService::Error => e
    Rails.logger.warn("Nao foi possivel cancelar checkout Cielo #{@reserva_payment&.payment_order_code}: #{e.message}")
    false
  rescue => e
    Rails.logger.error("Erro inesperado ao cancelar checkout Cielo #{@reserva_payment&.payment_order_code}: #{e.message}")
    false
  end

  private

  def transaction_query(filial)
    CieloCheckoutService::TransactionQuery.new(
      client_id: filial.cielo_checkout_client_id_for_payments,
      client_secret: filial.cielo_checkout_client_secret_for_payments
    )
  end

  def checkout_order_number
    CieloCheckoutService.checkout_order_number_from(
      @reserva_payment.payment_link_id,
      @reserva_payment.payment_order_code
    )
  end

  def remember_checkout_order_number(value)
    return if value.blank?

    @reserva_payment.update_column(:payment_link_id, value) if checkout_order_number.blank?
  end
end
