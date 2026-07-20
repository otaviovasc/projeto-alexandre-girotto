class AddGuestChangeLockToServicePurchases < ActiveRecord::Migration[7.0]
  def change
    add_column :cart_items, :purchased_after_service_deadline, :boolean, default: false, null: false
    add_column :reserva_services, :purchased_after_service_deadline, :boolean, default: false, null: false
  end
end
