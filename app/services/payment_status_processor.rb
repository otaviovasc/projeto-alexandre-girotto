class PaymentStatusProcessor
  def self.call(identifiers:, status:)
    new(identifiers: identifiers, status: status).call
  end

  def initialize(identifiers:, status:)
    @identifiers = Array(identifiers).compact_blank.uniq
    @status = status.to_s
  end

  def call
    return if @identifiers.blank? || @status.blank?

    process_cart_items_payment
    process_portal_services_payment
    process_reserva_payments
  end

  private

  def process_cart_items_payment
    cart_items = CartItem.where(payment_link_id: @identifiers)
                         .or(CartItem.where(payment_order_code: @identifiers))
    return if cart_items.empty?

    case @status
    when "paid"
      finalize_paid_cart_items(cart_items.where.not(payment_status: "paid"))
    when "waiting_payment", "pending"
      cart_items.where.not(payment_status: "paid").update_all(payment_status: "waiting_payment", updated_at: Time.current)
    when "unpaid", "refused", "failed"
      cart_items.where.not(payment_status: "paid").update_all(payment_status: "refused", updated_at: Time.current)
    when "canceled", "cancelled"
      cart_items.where.not(payment_status: "paid").update_all(payment_status: "refused", updated_at: Time.current)
    end
  end

  def finalize_paid_cart_items(cart_items)
    created_reserva_services = []
    cart_item_late_fees = service_late_fee_amounts_for_cart_items(cart_items)

    CartItem.transaction do
      cart_items.lock.includes(:item, :service, :reserva).find_each do |cart_item|
        next if cart_item.payment_status == "paid"

        if cart_item.item.present?
          ReservaItem.create!(
            reserva: cart_item.reserva,
            item: cart_item.item,
            quantity: cart_item.quantity
          )
        elsif cart_item.service.present?
          service_attributes = {
            reserva: cart_item.reserva,
            service: cart_item.service,
            quantity: cart_item.quantity,
            service_date: cart_item.service_date || cart_item.reserva.start_date,
            status: "active",
            payment_status: "paid",
            payment_link_id: cart_item.payment_link_id,
            payment_link_url: cart_item.payment_link_url,
            payment_order_code: cart_item.payment_order_code,
            payment_expires_at: cart_item.payment_expires_at,
            unit_price_paid: cart_item.unit_price_paid,
            total_paid: cart_item.total_paid,
            paid_at: Time.current,
            observation: cart_item.observation.presence
          }
          if ReservaService.column_names.include?("purchased_after_service_deadline")
            service_attributes[:purchased_after_service_deadline] = cart_item.respond_to?(:purchased_after_service_deadline?) && cart_item.purchased_after_service_deadline?
          end
          service_attributes[:service_late_fee_amount] = cart_item_late_fees[cart_item.id] if ReservaService.column_names.include?("service_late_fee_amount")

          reserva_service = ReservaService.create!(service_attributes)
          copy_photo_print_attachments(cart_item, reserva_service)
          created_reserva_services << reserva_service
        end

        increment_reserva_total!(cart_item.reserva, (cart_item.total_paid || 0).to_d + cart_item_late_fees.fetch(cart_item.id, 0.to_d))
        cart_item.destroy!
      end
    end

    export_service_purchases_to_sheets(created_reserva_services)
  end

  def process_portal_services_payment
    portal_services = ReservaService.where(payment_link_id: @identifiers)
                                    .or(ReservaService.where(payment_order_code: @identifiers))
    return if portal_services.empty?

    case @status
    when "paid"
      finalize_paid_portal_services(portal_services)
    when "waiting_payment", "pending"
      portal_services.where.not(payment_status: "paid").update_all(payment_status: "waiting_payment", updated_at: Time.current)
    when "unpaid", "refused", "failed"
      portal_services.where.not(payment_status: "paid").update_all(status: "pending_portal", payment_status: "refused", updated_at: Time.current)
    when "canceled", "cancelled"
      portal_services.where.not(payment_status: "paid").update_all(status: "cancelled", payment_status: "canceled", updated_at: Time.current)
    end
  end

  def process_reserva_payments
    reserva_payments = ReservaPayment.where(payment_link_id: @identifiers)
                                     .or(ReservaPayment.where(payment_order_code: @identifiers))
    return if reserva_payments.empty?

    reserva_payments.includes(:reserva).find_each do |reserva_payment|
      ReservaPaymentProcessor.call(reserva_payment: reserva_payment, status: @status)
    end
  end

  def finalize_paid_portal_services(portal_services)
    paid_at = Time.current
    newly_paid_service_ids = []

    ReservaService.transaction do
      newly_paid_services = portal_services
                            .lock
                            .where.not(payment_status: "paid")
                            .includes(:service, :reserva)
                            .to_a

      newly_paid_service_ids = newly_paid_services.map(&:id)
      newly_paid_services.each { |reserva_service| ensure_paid_amount!(reserva_service) }
      increment_reserva_totals!(newly_paid_services)

      ReservaService.where(id: newly_paid_service_ids).update_all(
        status: "active",
        payment_status: "paid",
        paid_at: paid_at,
        updated_at: paid_at
      )
    end

    return if newly_paid_service_ids.empty?

    export_service_purchases_to_sheets(
      ReservaService.includes(:reserva, :service).where(id: newly_paid_service_ids)
    )
  end

  def ensure_paid_amount!(reserva_service)
    return if reserva_service.unit_price_paid.present? && reserva_service.total_paid.present?

    unit_price = reserva_service.service.price_for(reserva_service.reserva) || 0
    quantity = reserva_service.quantity || 1

    reserva_service.update_columns(
      unit_price_paid: unit_price,
      total_paid: unit_price * quantity,
      updated_at: Time.current
    )
  end

  def increment_reserva_totals!(reserva_services)
    reserva_services.group_by(&:reserva).each do |reserva, services|
      total = services.sum { |reserva_service| (reserva_service.total_paid || 0).to_d + service_late_fee_amount_for(reserva_service) }
      increment_reserva_total!(reserva, total)
    end
  end

  def service_late_fee_amounts_for_cart_items(cart_items)
    amounts_by_id = {}
    assigned_by_order = {}

    cart_items.includes(:reserva, :service).order(:payment_order_code, :id).find_each do |cart_item|
      amount = if cart_item.has_attribute?(:service_late_fee_amount)
                 (cart_item.service_late_fee_amount || 0).to_d
               elsif cart_item.service.present? && cart_item.respond_to?(:purchased_after_service_deadline?) && cart_item.purchased_after_service_deadline?
                 late_fee_amount_for_first_item_in_order(cart_item, assigned_by_order)
               else
                 0.to_d
               end

      amounts_by_id[cart_item.id] = amount
    end

    amounts_by_id
  end

  def late_fee_amount_for_first_item_in_order(cart_item, assigned_by_order)
    return 0.to_d if cart_item.reserva.blank?

    order_key = [
      cart_item.reserva_id,
      cart_item.payment_order_code.presence || cart_item.payment_link_id.presence || cart_item.cart_id
    ]
    return 0.to_d if assigned_by_order[order_key]

    assigned_by_order[order_key] = true
    cart_item.reserva.service_purchase_late_fee_amount
  end

  def service_late_fee_amount_for(record)
    return 0.to_d unless record.respond_to?(:service_late_fee_amount)

    (record.service_late_fee_amount || 0).to_d
  end

  def increment_reserva_total!(reserva, amount)
    return if reserva.blank? || amount.blank?

    reserva.with_lock do
      reserva.update_column(:total_price, (reserva.total_price || 0) + amount)
    end
  end

  def export_service_purchases_to_sheets(reserva_services)
    reserva_services = Array(reserva_services).compact
    return if reserva_services.empty? || !GoogleSheetsExportService.configured?

    result = GoogleSheetsExportService.export_service_purchases(reserva_services)
    Rails.logger.warn("Google Sheets service purchases export failed: #{result[:error]}") unless result[:success]
  rescue => e
    Rails.logger.error("Google Sheets service purchases export error: #{e.message}")
  end

  def copy_photo_print_attachments(cart_item, reserva_service)
    if cart_item.photo_print_images.attached?
      reserva_service.photo_print_images.attach(cart_item.photo_print_images.attachments.map(&:blob))
    end

    reserva_service.photo_print_pdf.attach(cart_item.photo_print_pdf.blob) if cart_item.photo_print_pdf.attached?
  end
end
