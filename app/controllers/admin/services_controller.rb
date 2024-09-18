class Admin::ServicesController < ApplicationController
  before_action :set_service, only: [:edit, :update, :destroy]

  def index
    @services = Service.all
  end

  def new
    @service = Service.new
  end

  def create
    @service = Service.new(service_params)
    if @service.save
      @service.images.attach(params[:service][:images]) if params[:service][:images].present?
      redirect_to admin_services_path, notice: 'Service was successfully created.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      @service.images.attach(params[:service][:images]) if params[:service][:images].present?
      redirect_to admin_services_path, notice: 'Service was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @service.destroy
    redirect_to admin_services_path, notice: 'Service was successfully deleted.'
  end

  private

  def set_service
    @service = Service.find(params[:id])
  end

  def service_params
    params.require(:service).permit(:name, :description, :price, :duration, :options, :start_time, :end_time, :filial_id, :user_id)
  end
end
