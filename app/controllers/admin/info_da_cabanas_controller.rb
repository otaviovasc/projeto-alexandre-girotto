class Admin::InfoDaCabanasController < ApplicationController
  before_action :authorize_admin
  before_action :set_cabana
  before_action :set_info_da_cabana, only: [:edit, :update, :destroy]

  def index
    @info_da_cabanas = @cabana.info_da_cabanas
  end

  def new
    @info_da_cabana = @cabana.info_da_cabanas.new
  end

  def create
    @info_da_cabana = @cabana.info_da_cabanas.new(info_da_cabana_params)
    if @info_da_cabana.save
      redirect_to admin_cabana_info_da_cabanas_path(@cabana), notice: 'Info was successfully created.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @info_da_cabana.update(info_da_cabana_params)
      redirect_to admin_cabana_info_da_cabanas_path(@cabana), notice: 'Info was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @info_da_cabana.destroy
    redirect_to admin_cabana_info_da_cabanas_path(@cabana), notice: 'Info was successfully deleted.'
  end

  private

  def set_cabana
    @cabana = Cabana.find(params[:cabana_id])
  end

  def set_info_da_cabana
    @info_da_cabana = @cabana.info_da_cabanas.find(params[:id])
  end

  def info_da_cabana_params
    params.require(:info_da_cabana).permit(:info_type, :title, :content, :image)
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
