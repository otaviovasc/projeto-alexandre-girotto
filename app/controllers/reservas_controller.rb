class ReservasController < ApplicationController
  layout "clientside"
  before_action :set_reserva, only: [:show]

  def index
    @reservas = current_user.reservas
  end

  def show
  end

  def new
    @cabana = Cabana.find(params[:cabana_id])
    @reserva = @cabana.reservas.new
    @breakfast_service = Service.find_by(name: 'Café da Manhã')
  end

  def create
    @cabana = Cabana.find(params[:cabana_id])
    @reserva = @cabana.reservas.new(reserva_params)
    @reserva.user = current_user

    # First, try to save the reserva without services
    if @reserva.save
      # If breakfast is selected, create ReservaService
      if params[:reserva][:include_breakfast] == "1"
        service = Service.find_by(name: 'Café da Manhã')
        ReservaService.create(reserva: @reserva, service: service, quantity: params[:reserva][:breakfast_quantity].to_i)
      end

      # Recalculate total_price after services are added
      total_price = @reserva.calculate_total_price
      @reserva.update_column(:total_price, total_price)  # Skips validations
      redirect_to reserva_path(@reserva), notice: 'Reserva criada com sucesso.'
    else
      redirect_to new_cabana_reserva_path(@cabana), alert: "ERRO: #{@reserva.errors.full_messages.join("\n")}"
    end
  end


  def unavailable_dates
    @cabana = Cabana.find(params[:cabana_id])
    reservas = @cabana.reservas

    unavailable_dates = reservas.map do |reserva|
      (reserva.start_date...reserva.end_date).to_a
    end.flatten

    render json: unavailable_dates
  end

  def calculate_price
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])
    include_breakfast = params[:include_breakfast] == 'true'
    breakfast_quantity = params[:breakfast_quantity].to_i

    cabana = Cabana.find(params[:cabana_id])
    reserva = Reserva.new(start_date: start_date, end_date: end_date, cabana: cabana)

    total_price = reserva.calculate_total_price || 0  # Ensure total_price is a number

    if include_breakfast
      breakfast_service = Service.find_by(name: 'Café da Manhã')
      days_stayed = (start_date...end_date).count
      total_price += breakfast_service.price * days_stayed * breakfast_quantity
    end

    render json: { total_price: total_price.to_f }  # Ensure total_price is a float
  end


  private

  def set_reserva
    @reserva = current_user.reservas.find(params[:id])
  end

  def reserva_params
    params.require(:reserva).permit(:start_date, :end_date)
  end
end
