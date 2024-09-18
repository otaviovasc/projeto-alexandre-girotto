class ReservaItemsController < ApplicationController
  def create
    @reserva = Reserva.find(params[:reserva_id])
    item = Item.find(params[:item_id])
    quantity = params[:quantity].to_i

    if item.quantity < quantity
      redirect_to marketplace_items_path, alert: 'Not enough stock available.'
    else
      item.update(quantity: item.quantity - quantity)
      @reserva_item = ReservaItem.new(reserva: @reserva, item: item, quantity: quantity)

      if @reserva_item.save
        redirect_to marketplace_items_path, notice: 'Item added to your reservation.'
      else
        redirect_to marketplace_items_path, alert: 'Unable to add item.'
      end
    end
  end
end
