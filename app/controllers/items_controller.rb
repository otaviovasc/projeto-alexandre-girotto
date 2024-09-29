# app/controllers/items_controller.rb
class ItemsController < ApplicationController
  layout "clientside"
  def show
    @item = Item.find(params[:id])
  end
end
