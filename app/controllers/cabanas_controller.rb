class CabanasController < ApplicationController
  layout "clientside"
  skip_before_action :authenticate_user!
  def index
    if params[:filial_id].present?
      @cabanas = Cabana.where(filial_id: params[:filial_id])
      # @infos_da_cabana = @cabanas.info_da_cabanas
    else
      @cabanas = Cabana.all
      # @infos_da_cabana = @cabanas.info_da_cabanas
    end
  end

  def show
    @cabana = Cabana.find(params[:id])
    @infos_da_cabana = InfoDaCabana.where(cabana_id: @cabana.id)
  end
end
