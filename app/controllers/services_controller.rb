# app/controllers/services_controller.rb
class ServicesController < ApplicationController
  layout "clientside"
  def show
    @service = Service.find(params[:id])
  end
end
