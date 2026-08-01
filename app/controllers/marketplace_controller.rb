class MarketplaceController < ApplicationController
  layout "clientside"
  before_action :check_active_reserva

  def services
    @services = @reserva.cabana.filial.services
                       .where(show_in_marketplace: [true, nil])
                       .order(:name)
                       .reject(&:hidden_from_guests?)
  end

  def items
    @items = @reserva.cabana.filial.items
                    .where(show_in_marketplace: [true, nil])
                    .order(:name)
  end

  def show_service
    @service = Service.find(params[:id])
    redirect_to services_marketplace_index_path, alert: 'Serviço não encontrado.' and return if @service.hidden_from_guests?
  end

  def show_item
    @item = Item.find(params[:id])
  end

  private

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
      redirect_to root_path, alert: 'Você precisa de uma reserva paga para acessar a loja.'
    end
  end
end
