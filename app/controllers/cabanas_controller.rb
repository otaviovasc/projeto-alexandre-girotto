class CabanasController < ApplicationController
  layout "clientside"
  skip_before_action :authenticate_user!
  def index
    if params[:filial_id].present?
      @cabanas = Cabana.where(filial_id: params[:filial_id])
    else
      @cabanas = Cabana.all
    end
  end

  def show
    @cabana = Cabana.find(params[:id])
    @infos_da_cabana = InfoDaCabana.where(cabana_id: @cabana.id)
  end
end
