class Admin::CabanasController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_cabana, only: [:edit, :update, :destroy, :show, :price_rules_and_holidays]

  def index
    @cabanas = Cabana.all
  end

  def new
    @cabana = Cabana.new
  end

  def create
    @cabana = Cabana.new(cabana_params)

    if @cabana.save
      @cabana.images.attach(params[:cabana][:images]) if params[:cabana][:images].present?
      redirect_to admin_cabanas_path, notice: 'Cabana was successfully created.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @cabana.update(cabana_params)
      @cabana.images.attach(params[:cabana][:images]) if params[:cabana][:images].present?
      redirect_to admin_cabanas_path, notice: 'Cabana was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @cabana.destroy
    redirect_to admin_cabanas_path, notice: 'Cabana was successfully deleted.'
  end

  def price_rules_and_holidays
    @price_rule = PriceRule.new
    @holidays = Holiday.all
    @holiday = Holiday.new
  end

  private

  def set_cabana
    @cabana = Cabana.find(params[:id])
  end

  def cabana_params
    params.require(:cabana).permit(:name, :price, :filial_id)
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
