class ReservaServicesController < ApplicationController
  def create
    @reserva = Reserva.find(params[:reserva_id])
    service = Service.find(params[:service_id])
    quantity = params[:quantity].to_i

    @reserva_service = ReservaService.new(reserva: @reserva, service: service, quantity: quantity)

    if @reserva_service.save
      redirect_to services_marketplace_index_path, notice: 'Service added to your reservation.'
    else
      redirect_to services_marketplace_index_path, alert: 'Unable to add service.'
    end
  end
end
