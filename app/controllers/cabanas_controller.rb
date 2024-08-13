class CabanasController < ApplicationController
  before_action :authenticate_user!

  def index
    @cabanas = Cabana.all
  end

  def show
    @cabana = Cabana.find(params[:id])
    @reserva = Reserva.new # For creating a reservation on the Cabana show page
  end
end
