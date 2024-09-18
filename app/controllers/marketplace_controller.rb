class MarketplaceController < ApplicationController
  before_action :check_active_reserva

  def services
    filial_id = @reserva.cabana.filial_id
    @services = Service.where(filial_id: filial_id)
  end

  def items
    filial_id = @reserva.cabana.filial_id
    @items = Item.where(filial_id: filial_id, show_in_marketplace: true).where('quantity > 0')
  end

  private

  def check_active_reserva
    @reserva = current_user.reservas.find_by('start_date <= ? AND end_date >= ?', Date.today, Date.today)
    unless @reserva
      redirect_to root_path, alert: 'Você precisa de uma reserva ativa para acessar a loja.'
    end
  end
end
