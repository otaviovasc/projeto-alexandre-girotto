class MarketplaceController < ApplicationController
  layout "clientside"
  before_action :check_active_reserva

  def services
    @services = Service.where(filial_id: @reserva.cabana.filial_id)
  end

  def items
    @items = Item.where(filial_id: @reserva.cabana.filial_id, show_in_marketplace: true)
  end

  def show_service
    @service = Service.find(params[:id])
  end

  def show_item
    @item = Item.find(params[:id])
  end

  private

  def check_active_reserva
    @reserva = current_user.reservas.find_by(
      payment_status: 'paid'
    )

    unless @reserva
      redirect_to root_path, alert: 'Você precisa de uma reserva ativa para acessar a loja.'
    end
  end
end
