class MarketplaceController < ApplicationController
  layout "clientside"
  before_action :check_active_reserva

  def services
    @services = Service.where(filial_id: @reserva.cabana.filial_id)
    load_cart_items
  end

  def items
    @items = Item.where(filial_id: @reserva.cabana.filial_id, show_in_marketplace: true)
    load_cart_items
  end

  def show_service
    @service = Service.find(params[:id])
  end

  def show_item
    @item = Item.find(params[:id])
  end

  private

  def check_active_reserva
    @reserva = current_user.reservas.find_by('start_date <= ? AND end_date >= ?', Date.today, Date.today)
    unless @reserva
      redirect_to root_path, alert: 'Você precisa de uma reserva ativa para acessar a loja.'
    end
  end

  def load_cart_items
    @cart_items = current_user.cart.cart_items.includes(:item, :service)
  end
end
