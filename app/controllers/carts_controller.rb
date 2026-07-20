class CartsController < ApplicationController
  layout "clientside"
  helper_method :cart_item_unit_price
  before_action :find_or_create_cart
  before_action :check_active_reserva
  before_action :ensure_service_purchase_window_open_for_service!, only: [:add_item, :update_item]

  def add_item
    if params[:item_id].present?
      item = @reserva.cabana.filial.items.find(params[:item_id])
      @cart_item = @cart.cart_items.find_or_initialize_by(item: item)
      redirect_fallback = items_marketplace_index_path
    elsif params[:service_id].present?
      service = @reserva.cabana.filial.services.find(params[:service_id])
      @cart_item = @cart.cart_items.find_or_initialize_by(service: service)
      redirect_fallback = services_marketplace_index_path
    end

    @cart_item.reserva = @reserva
    @cart_item.quantity = params[:quantity].to_i if params[:quantity].present?
    if @cart_item.save
      redirect_to redirect_fallback, notice: 'Adicionado ao carrinho.'
    else
      redirect_to redirect_fallback, alert: 'Erro ao adicionar no carrinho.'
    end
  end

  def update_item
    redirect_fallback = checkout_cart_path
    if params[:item_id].present?
      item = @reserva.cabana.filial.items.find(params[:item_id])
      @cart_item = @cart.cart_items.find_or_initialize_by(item: item)
    elsif params[:service_id].present?
      service = @reserva.cabana.filial.services.find(params[:service_id])
      @cart_item = @cart.cart_items.find_or_initialize_by(service: service)
    end

    @cart_item.reserva = @reserva
    @cart_item.quantity = params[:quantity].to_i if params[:quantity].present?
    if @cart_item.save
      redirect_to redirect_fallback, notice: 'Item atualizado no carrinho.'
    else
      redirect_to redirect_fallback, alert: 'Erro ao atualizar item no carrinho.'
    end
  end

  def remove_item
    @cart_item = @cart.cart_items.find(params[:id])
    @cart_item.destroy
    redirect_to checkout_cart_path
  end

  # Display checkout page
  def checkout
    discard_closed_service_cart_items
    @cart_items = payable_cart_items.includes(:item, :service)
  end

  # Payment page action
  def payment
    @pending_payment = active_pending_payment
    sync_cielo_checkout_status!(@pending_payment) if @pending_payment.present?
    @pending_payment = active_pending_payment
    @cart_items = @cart.cart_items.includes(:item, :service)
  end

  def checkout_process
    removed_services = discard_closed_service_cart_items

    pending_payment = active_pending_payment
    if pending_payment.present? && payable_cart_items.empty?
      redirect_to pending_payment.payment_link_url, allow_other_host: true, status: :see_other
      return
    end

    @cart_items = payable_cart_items.includes(:item, :service, reserva: { cabana: :filial })
    if @cart_items.empty?
      alert = removed_services ? @reserva.service_purchase_closed_message : 'Seu carrinho esta vazio.'
      redirect_to checkout_cart_path, alert: alert
      return
    end

    payment_link = create_cart_payment_link(@cart_items)

    redirect_to payment_link['url'], allow_other_host: true, status: :see_other
  rescue PagarmePaymentLinkService::Error, CieloCheckoutService::Error => e
    Rails.logger.error("Cart payment error: #{e.message}")
    redirect_to checkout_cart_path, alert: e.message
  rescue => e
    Rails.logger.error("Unexpected cart payment error: #{e.message}")
    redirect_to checkout_cart_path, alert: 'Nao foi possivel iniciar o pagamento. Tente novamente.'
  end

  private

  def find_or_create_cart
    @cart = current_user.cart || current_user.create_cart
  end

  def check_active_reserva
    @reserva = current_user.reservas
                           .includes(cabana: :filial)
                           .where(payment_status: 'paid')
                           .where('end_date >= ?', Date.current)
                           .order(start_date: :asc, created_at: :desc)
                           .first

    @reserva ||= current_user.reservas
                            .includes(cabana: :filial)
                            .where(payment_status: 'paid')
                            .order(created_at: :desc)
                            .first
    unless @reserva
      redirect_to root_path, alert: 'Voce precisa de uma reserva paga para acessar a loja.'
    end
  end

  def payable_cart_items
    @cart.cart_items.where(payment_status: [nil, 'refused'])
  end

  def active_pending_payment
    @cart.cart_items
         .where(payment_status: 'waiting_payment')
         .where('payment_expires_at IS NULL OR payment_expires_at > ?', Time.current)
         .where.not(payment_link_url: nil)
         .first
  end

  def ensure_service_purchase_window_open_for_service!
    return unless params[:service_id].present?
    return if @reserva.service_purchase_window_open?

    @cart.cart_items.where(service_id: params[:service_id]).where(payment_status: [nil, 'refused']).destroy_all
    redirect_to services_marketplace_index_path, alert: @reserva.service_purchase_closed_message
  end

  def discard_closed_service_cart_items
    return false if @reserva.service_purchase_window_open?

    service_items = payable_cart_items.where.not(service_id: nil)
    return false if service_items.empty?

    service_items.destroy_all
    flash.now[:alert] = @reserva.service_purchase_closed_message
    true
  end

  def create_cart_payment_link(cart_items)
    order_code = cart_payment_order_code(cart_items)
    expires_in = 10
    payment_link = if use_cielo_checkout_for_cart?(cart_items)
                     CieloCheckoutService.new(
                       merchant_id: @reserva.cabana.filial.cielo_checkout_merchant_id_for_payments,
                       order_code: order_code,
                       items: payment_cart_items(cart_items),
                       return_url: payment_cart_url,
                       customer: payment_customer,
                       soft_descriptor: "VILLAGGIO",
                       max_installments: @reserva.service_max_installments
                     ).call
                   else
                     PagarmePaymentLinkService.new(
                       api_key: @reserva.cabana.filial.pagarme_api_key_for_payments,
                       name: "Carrinho Reserva #{@reserva.id}",
                       order_code: order_code,
                       items: payment_cart_items(cart_items),
                       success_url: payment_cart_url,
                       failure_url: checkout_cart_url,
                       expires_in: expires_in,
                       max_installments: service_only_cart?(cart_items) ? @reserva.service_max_installments : 1,
                       credit_card_interest_rate: service_credit_card_interest_rate(cart_items)
                     ).call
                   end

    payment_expires_at = expires_in.minutes.from_now
    now = Time.current

    cart_items.find_each do |cart_item|
      unit_price = cart_item_unit_price(cart_item) || 0
      quantity = cart_item.quantity || 1

      cart_item.update_columns(
        payment_status: 'waiting_payment',
        payment_link_id: payment_link['id'],
        payment_link_url: payment_link['url'],
        payment_order_code: order_code,
        payment_expires_at: payment_expires_at,
        unit_price_paid: unit_price,
        total_paid: unit_price * quantity,
        purchased_after_service_deadline: cart_item.service.present? && @reserva.service_purchase_override_used?,
        updated_at: now
      )
    end

    payment_link
  end

  def payment_cart_items(cart_items)
    items = cart_items.map do |cart_item|
      product = cart_item.item || cart_item.service

      {
        id: cart_item.id,
        name: product.name,
        unit_price: cart_item_unit_price(cart_item),
        quantity: cart_item.quantity
      }
    end

    return items if items.size <= 10

    [{
      id: "cart-#{@cart.id}",
      name: "Itens adicionais - Reserva #{@reserva.id}",
      unit_price: cart_items.sum { |cart_item| cart_item_unit_price(cart_item) * cart_item.quantity },
      quantity: 1
    }]
  end

  def cart_item_unit_price(cart_item)
    return cart_item.item.price if cart_item.item.present?

    cart_item.service.price_for(@reserva)
  end

  def service_only_cart?(cart_items)
    cart_items.all? { |cart_item| cart_item.service_id.present? }
  end

  def use_cielo_checkout_for_cart?(cart_items)
    ServicePaymentProvider.cielo_checkout? && service_only_cart?(cart_items)
  end

  def cart_payment_order_code(cart_items)
    if use_cielo_checkout_for_cart?(cart_items)
      "CT#{@cart.id.to_s.last(6)}#{Time.current.to_i}"
    else
      "cart-#{@cart.id}-#{Time.current.to_i}"
    end
  end

  def payment_customer
    {
      name: current_user&.name,
      email: current_user&.email,
      phone: current_user&.telephone
    }
  end

  def service_credit_card_interest_rate(cart_items)
    service_only_cart?(cart_items) && @reserva.partnership_reservation? ? 3 : 0
  end

  def sync_cielo_checkout_status!(cart_item)
    return unless ServicePaymentProvider.cielo_checkout?
    return if cart_item.payment_order_code.blank?

    CieloPendingPaymentSync.sync_order_code(
      order_code: cart_item.payment_order_code,
      filial: @reserva.cabana.filial
    )
  rescue CieloCheckoutService::Error => e
    Rails.logger.warn("Unable to sync Cielo Checkout cart status: #{e.message}")
  rescue => e
    Rails.logger.error("Unexpected Cielo Checkout cart sync error: #{e.message}")
  end
end
