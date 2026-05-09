class AddPaidAmountFieldsToReservaServicesAndCartItems < ActiveRecord::Migration[7.0]
  def change
    add_column :reserva_services, :unit_price_paid, :decimal, precision: 10, scale: 2
    add_column :reserva_services, :total_paid, :decimal, precision: 10, scale: 2
    add_column :reserva_services, :paid_at, :datetime

    add_column :cart_items, :unit_price_paid, :decimal, precision: 10, scale: 2
    add_column :cart_items, :total_paid, :decimal, precision: 10, scale: 2
    add_column :cart_items, :paid_at, :datetime
  end
end
