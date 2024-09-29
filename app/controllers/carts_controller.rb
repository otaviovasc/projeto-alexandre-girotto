class CartsController < ApplicationController
  before_action :find_or_create_cart
  before_action :check_active_reserva

  def add_item
    if params[:item_id].present?
      item = Item.find(params[:item_id])
      @cart_item = @cart.cart_items.find_or_initialize_by(item: item)
      redirect_fallback = items_marketplace_index_path
    elsif params[:service_id].present?
      service = Service.find(params[:service_id])
      @cart_item = @cart.cart_items.find_or_initialize_by(service: service)
      redirect_fallback = services_marketplace_index_path
    end

    @cart_item.reserva = @reserva
    @cart_item.quantity = params[:quantity].to_i if params[:quantity].present?
    if @cart_item.save
      redirect_to redirect_fallback, notice: 'Added to cart successfully!'
    else
      redirect_to redirect_fallback, alert: 'Failed to add to cart.'
    end
  end

  def remove_item
    @cart_item = @cart.cart_items.find(params[:id])
    @cart_item.destroy
    render json: { status: 'success', cart: @cart }
  end

  # Display checkout page
  def checkout
    @cart_items = @cart.cart_items.includes(:item, :service)
  end

  # Payment page action
  def payment
    @cart_items = @cart.cart_items.includes(:item, :service)
  end

  # Simulate payment and finalize reservation
  def checkout_process
    @cart_items = @cart.cart_items

    # Link items and services to the current user's reservation
    reserva = current_user.reservas.find_by('start_date <= ? AND end_date >= ?', Date.today, Date.today)

    @cart_items.each do |cart_item|
      if cart_item.item.present?
        ReservaItem.create(reserva: reserva, item: cart_item.item, quantity: cart_item.quantity)
      elsif cart_item.service.present?
        ReservaService.create(reserva: reserva, service: cart_item.service, quantity: cart_item.quantity)
      end
    end

    # Clear the cart after checkout
    @cart.cart_items.destroy_all

    redirect_to reserva_path(reserva), notice: 'Checkout complete! Items added to your reservation.'
  end

  private

  def find_or_create_cart
    @cart = current_user.cart || current_user.create_cart
  end

  def check_active_reserva
    @reserva = current_user.reservas.find_by('start_date <= ? AND end_date >= ?', Date.today, Date.today)
    unless @reserva
      redirect_to root_path, alert: 'Você precisa de uma reserva ativa para acessar a loja.'
    end
  end
end
