class Admin::ReservasController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_reserva, only: [:edit, :update, :destroy, :show]

  def index
    @reservas = Reserva.all
  end

  def new
    @reserva = Reserva.new
  end

  def create
    @reserva = Reserva.new(reserva_params)
    if @reserva.save
      redirect_to admin_reservas_path, notice: 'Reserva was successfully created.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @reserva.update(reserva_params)
      redirect_to admin_reservas_path, notice: 'Reserva was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @reserva.destroy
    redirect_to admin_reservas_path, notice: 'Reserva was successfully deleted.'
  end

  private

  def set_reserva
    @reserva = Reserva.find(params[:id])
  end

  def reserva_params
    params.require(:reserva).permit(:start_date, :end_date, :cabana_id, :user_id)
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
