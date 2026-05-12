class ReservaServicesController < ApplicationController
  def create
    @reserva = Reserva.find(params[:reserva_id])
    unless @reserva.service_purchase_window_open?
      redirect_to services_marketplace_index_path, alert: @reserva.service_purchase_closed_message and return
    end

    service = Service.find(params[:service_id])
    quantity = params[:quantity].to_i

    @reserva_service = ReservaService.new(reserva: @reserva, service: service, quantity: quantity)

    if @reserva_service.save
      redirect_to services_marketplace_index_path, notice: 'Serviço adicionado à reserva.'
    else
      redirect_to services_marketplace_index_path, alert: 'Não foi possivel adicionar o serviço, entre em contato com o suporte.'
    end
  end
end
