require 'openssl'

class PagamentosController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:webhook]
  skip_before_action :authenticate_user!, only: [:webhook]

  def webhook
    raw_body = request.raw_post
    unless valid_pagarme_signature?(raw_body)
      Rails.logger.warn('Rejected Pagar.me webhook with invalid signature.')
      head :unauthorized
      return
    end

    event = JSON.parse(raw_body)
    data = event['data'] || event
    status = data['status'] || data['current_status'] || event['status'] || event['current_status']
    identifiers = [data['id'], data['code'], event['id'], event['code']].compact.uniq

    process_cart_items_payment(identifiers, status)
    process_portal_services_payment(identifiers, status)
    process_reserva_payment(identifiers, status)

    head :ok
  rescue => e
    Rails.logger.error("Error processing webhook: #{e.message}")
    head :bad_request
  end

  private

  def valid_pagarme_signature?(raw_body)
    signature = request.headers['X-Hub-Signature'].to_s
    return !require_pagarme_webhook_signature? if signature.blank?

    pagarme_webhook_keys.any? do |api_key|
      expected = OpenSSL::HMAC.hexdigest('SHA1', api_key, raw_body)
      secure_signature_match?(signature, expected)
    end
  end

  def require_pagarme_webhook_signature?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('PAGARME_REQUIRE_WEBHOOK_SIGNATURE', false))
  end

  def pagarme_webhook_keys
    env_keys = %w[BRAUNA SERRA].filter_map { |suffix| ENV["PAGARME_API_KEY_#{suffix}"].presence }
    db_keys = Filial.all.filter_map { |filial| filial.pagarme_api_key_for_payments.presence }

    (env_keys + db_keys).uniq
  rescue => e
    Rails.logger.error("Unable to load Pagar.me webhook keys: #{e.message}")
    []
  end

  def secure_signature_match?(signature, expected)
    [expected, "sha1=#{expected}"].any? do |candidate|
      signature.bytesize == candidate.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(signature, candidate)
    end
  end

  def process_cart_items_payment(identifiers, status)
    return if identifiers.blank?

    cart_items = CartItem.where(payment_link_id: identifiers)
                         .or(CartItem.where(payment_order_code: identifiers))
    return if cart_items.empty?

    case status
    when 'paid'
      finalize_paid_cart_items(cart_items.where.not(payment_status: 'paid'))
    when 'waiting_payment', 'pending'
      cart_items.where.not(payment_status: 'paid').update_all(payment_status: 'waiting_payment', updated_at: Time.current)
    when 'unpaid', 'refused', 'failed'
      cart_items.where.not(payment_status: 'paid').update_all(payment_status: 'refused', updated_at: Time.current)
    when 'canceled', 'cancelled'
      cart_items.where.not(payment_status: 'paid').update_all(payment_status: 'refused', updated_at: Time.current)
    end
  end

  def finalize_paid_cart_items(cart_items)
    created_reserva_services = []

    CartItem.transaction do
      cart_items.lock.includes(:item, :service, :reserva).find_each do |cart_item|
        next if cart_item.payment_status == 'paid'

        if cart_item.item.present?
          ReservaItem.create!(
            reserva: cart_item.reserva,
            item: cart_item.item,
            quantity: cart_item.quantity
          )
        elsif cart_item.service.present?
          created_reserva_services << ReservaService.create!(
            reserva: cart_item.reserva,
            service: cart_item.service,
            quantity: cart_item.quantity,
            service_date: cart_item.service_date || cart_item.reserva.start_date,
            status: 'active',
            payment_status: 'paid',
            payment_link_id: cart_item.payment_link_id,
            payment_link_url: cart_item.payment_link_url,
            payment_order_code: cart_item.payment_order_code,
            payment_expires_at: cart_item.payment_expires_at,
            unit_price_paid: cart_item.unit_price_paid,
            total_paid: cart_item.total_paid,
            paid_at: Time.current,
            observation: cart_item.observation.presence
          )
        end

        increment_reserva_total!(cart_item.reserva, cart_item.total_paid)
        cart_item.destroy!
      end
    end

    export_service_purchases_to_sheets(created_reserva_services)
  end

  def process_portal_services_payment(identifiers, status)
    return if identifiers.blank?

    portal_services = ReservaService.where(payment_link_id: identifiers)
                                    .or(ReservaService.where(payment_order_code: identifiers))
    return if portal_services.empty?

    case status
    when 'paid'
      paid_at = Time.current
      newly_paid_service_ids = []

      ReservaService.transaction do
        newly_paid_services = portal_services
                              .lock
                              .where.not(payment_status: 'paid')
                              .includes(:service, :reserva)
                              .to_a

        newly_paid_service_ids = newly_paid_services.map(&:id)
        newly_paid_services.each { |reserva_service| ensure_paid_amount!(reserva_service) }
        increment_reserva_totals!(newly_paid_services)

        ReservaService.where(id: newly_paid_service_ids).update_all(
          status: 'active',
          payment_status: 'paid',
          paid_at: paid_at,
          updated_at: paid_at
        )
      end

      return if newly_paid_service_ids.empty?

      export_service_purchases_to_sheets(
        ReservaService.includes(:reserva, :service).where(id: newly_paid_service_ids)
      )
    when 'waiting_payment', 'pending'
      portal_services.where.not(payment_status: 'paid').update_all(payment_status: 'waiting_payment', updated_at: Time.current)
    when 'unpaid', 'refused', 'failed'
      portal_services.where.not(payment_status: 'paid').update_all(status: 'pending_portal', payment_status: 'refused', updated_at: Time.current)
    when 'canceled', 'cancelled'
      portal_services.where.not(payment_status: 'paid').update_all(status: 'cancelled', payment_status: 'canceled', updated_at: Time.current)
    end
  end

  def process_reserva_payment(identifiers, status)
    reserva = Reserva.find_by(payment_link_id: identifiers)
    reserva ||= reserva_from_order_code(identifiers)
    return unless reserva

    case status
    when 'paid'
      reserva.update_column(:payment_status, 'paid')
    when 'waiting_payment', 'pending'
      reserva.update_column(:payment_status, 'waiting_payment') unless reserva.paid?
    when 'unpaid', 'refused', 'failed'
      reserva.update_column(:payment_status, 'refused') unless reserva.paid?
    when 'canceled', 'cancelled'
      reserva.update_column(:payment_status, 'canceled') unless reserva.paid?
    end
  end

  def reserva_from_order_code(identifiers)
    order_code = identifiers.find { |identifier| identifier.to_s.match?(/\Areserva-\d+\z/) }
    return unless order_code

    Reserva.find_by(id: order_code.to_s.split('-').last)
  end

  def ensure_paid_amount!(reserva_service)
    return if reserva_service.unit_price_paid.present? && reserva_service.total_paid.present?

    unit_price = reserva_service.service.price || 0
    quantity = reserva_service.quantity || 1

    reserva_service.update_columns(
      unit_price_paid: unit_price,
      total_paid: unit_price * quantity,
      updated_at: Time.current
    )
  end

  def increment_reserva_totals!(reserva_services)
    reserva_services.group_by(&:reserva).each do |reserva, services|
      total = services.sum { |reserva_service| reserva_service.total_paid || 0 }
      increment_reserva_total!(reserva, total)
    end
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
end
