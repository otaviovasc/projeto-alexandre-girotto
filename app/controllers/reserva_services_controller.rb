class ReservaServicesController < ApplicationController
  def create
    @reserva = Reserva.find(params[:reserva_id])
    unless @reserva.service_purchase_window_open?
      redirect_to services_marketplace_index_path, alert: @reserva.service_purchase_closed_message and return
    end

    service = Service.find(params[:service_id])
    quantity = params[:quantity].to_i
    service_date = requested_service_date

    @reserva_service = ReservaService.find_or_initialize_by(reserva: @reserva, service: service)
    @reserva_service.quantity = quantity
    @reserva_service.service_date = service_date if service_date

    if @reserva_service.save
      redirect_to services_marketplace_index_path, notice: 'Serviço adicionado à reserva.'
    else
      redirect_to services_marketplace_index_path, alert: 'Não foi possivel adicionar o serviço, entre em contato com o suporte.'
    end
  end

  private

  def requested_service_date
    raw_date = params[:scheduled_date].presence || params[:service_date].presence || params[:date].presence
    return unless raw_date

    if raw_date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(raw_date)
    elsif raw_date.match?(/\A\d{1,2}\/\d{1,2}\/\d{4}\z/)
      Date.strptime(raw_date, "%d/%m/%Y")
    else
      Date.parse(raw_date)
    end
  rescue ArgumentError
    nil
  end
end
