class ReservasController < ApplicationController
  before_action :authenticate_user!
  before_action :set_reserva, only: [:show]

  def index
    @reservas = current_user.reservas
  end

  def show
  end

  def new
    @cabana = Cabana.find(params[:cabana_id])
    @reserva = @cabana.reservas.new
  end

  def create
    @cabana = Cabana.find(params[:cabana_id])
    @reserva = @cabana.reservas.new(reserva_params)
    @reserva.user = current_user

    if @reserva.save
      redirect_to reserva_path(@reserva), notice: 'Reserva criada com sucesso.'
    else
      render :new
    end
  end

  private

  def set_reserva
    @reserva = current_user.reservas.find(params[:id])
  end

  def reserva_params
    params.require(:reserva).permit(:start_date, :end_date)
  end
end
