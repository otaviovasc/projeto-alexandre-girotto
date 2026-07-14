class CieloPendingPaymentSync
  DEFAULT_LIMIT = 25
  DEFAULT_LOOKBACK_HOURS = 14 * 24

  Result = Struct.new(:checked, :paid, :refused, :canceled, :errors, keyword_init: true)

  def self.run(limit: nil, lookback_hours: nil)
    new(limit: limit, lookback_hours: lookback_hours).call
  end

  def initialize(limit: nil, lookback_hours: nil)
    @limit = positive_integer(limit || ENV["CIELO_PENDING_PAYMENT_SYNC_LIMIT"], DEFAULT_LIMIT)
    @lookback_hours = positive_integer(
      lookback_hours || ENV["CIELO_PENDING_PAYMENT_SYNC_LOOKBACK_HOURS"],
      DEFAULT_LOOKBACK_HOURS
    )
    @result = Result.new(checked: 0, paid: 0, refused: 0, canceled: 0, errors: 0)
  end

  def call
    return @result unless ServicePaymentProvider.cielo_checkout?

    pending_orders.each { |order| sync_order(order) }
    @result
  end

  private

  PendingOrder = Struct.new(:order_code, :filial, keyword_init: true)

  def pending_orders
    orders = []

    pending_cart_items.each do |cart_item|
      orders << PendingOrder.new(order_code: cart_item.payment_order_code, filial: cart_item.reserva&.cabana&.filial)
    end

    pending_reserva_services.each do |reserva_service|
      orders << PendingOrder.new(order_code: reserva_service.payment_order_code, filial: reserva_service.reserva&.cabana&.filial)
    end

    orders
      .select { |order| valid_order?(order) }
      .uniq { |order| order.order_code }
      .first(@limit)
  end

  def pending_cart_items
    CartItem
      .includes(reserva: { cabana: :filial })
      .where(payment_status: "waiting_payment")
      .where.not(payment_order_code: nil)
      .where("cart_items.created_at >= :cutoff OR cart_items.updated_at >= :cutoff", cutoff: cutoff_time)
      .order(:updated_at)
      .limit(scan_limit)
      .to_a
  end

  def pending_reserva_services
    ReservaService
      .includes(reserva: { cabana: :filial })
      .where(payment_status: "waiting_payment")
      .where.not(payment_order_code: nil)
      .where("reserva_services.created_at >= :cutoff OR reserva_services.updated_at >= :cutoff", cutoff: cutoff_time)
      .order(:updated_at)
      .limit(scan_limit)
      .to_a
  end

  def sync_order(order)
    @result.checked += 1

    transaction = transaction_query(order.filial).find_by_order_number(order.order_code)
    status = CieloCheckoutService.payment_status_from_transaction(transaction)

    return if status.blank? || status == "waiting_payment"

    checkout_order_number = transaction["checkoutOrderNumber"].presence || transaction["checkout_order_number"].presence
    remember_checkout_order_number(order.order_code, checkout_order_number)

    PaymentStatusProcessor.call(
      identifiers: [order.order_code, checkout_order_number].compact_blank,
      status: status
    )

    increment_result(status)
  rescue CieloCheckoutService::Error => e
    @result.errors += 1
    Rails.logger.warn("Erro ao sincronizar pagamento Cielo #{order.order_code}: #{e.message}")
  rescue => e
    @result.errors += 1
    Rails.logger.error("Erro inesperado ao sincronizar pagamento Cielo #{order.order_code}: #{e.message}")
  end

  def transaction_query(filial)
    CieloCheckoutService::TransactionQuery.new(
      client_id: filial.cielo_checkout_client_id_for_payments,
      client_secret: filial.cielo_checkout_client_secret_for_payments
    )
  end

  def remember_checkout_order_number(order_code, checkout_order_number)
    return if order_code.blank? || checkout_order_number.blank?

    now = Time.current
    CartItem.where(payment_order_code: order_code).update_all(payment_link_id: checkout_order_number, updated_at: now)
    ReservaService.where(payment_order_code: order_code).update_all(payment_link_id: checkout_order_number, updated_at: now)
  end

  def increment_result(status)
    case status
    when "paid"
      @result.paid += 1
    when "refused"
      @result.refused += 1
    when "canceled", "cancelled"
      @result.canceled += 1
    end
  end

  def valid_order?(order)
    order.order_code.to_s.match?(/\A(?:CT|PS)\d+\z/) && order.filial.present?
  end

  def cutoff_time
    @cutoff_time ||= @lookback_hours.hours.ago
  end

  def scan_limit
    @limit * 4
  end

  def positive_integer(value, default)
    integer = value.to_i
    integer.positive? ? integer : default
  end
end
