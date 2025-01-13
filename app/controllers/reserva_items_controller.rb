class ReservaItemsController < ApplicationController
  def create
    @reserva = Reserva.find(params[:reserva_id])
    item = Item.find(params[:item_id])
    quantity = params[:quantity].to_i

    if item.quantity < quantity
      redirect_to items_marketplace_index_path, alert: 'Quantidade indisponivel no estoque.'
    else
      item.update(quantity: item.quantity - quantity)
      @reserva_item = ReservaItem.new(reserva: @reserva, item: item, quantity: quantity)

      if @reserva_item.save
        redirect_to items_marketplace_index_path, notice: 'Item adicionado à sua reserva.'
      else
        redirect_to items_marketplace_index_path, alert: 'Não foi possivel adicionar o item, entre em contato com o suporte.'
      end
    end
  end
end
