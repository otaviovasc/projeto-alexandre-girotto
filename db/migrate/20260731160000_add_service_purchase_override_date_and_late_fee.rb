class AddServicePurchaseOverrideDateAndLateFee < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :service_purchase_override_until, :date
    add_column :reservas, :service_purchase_late_fee_waived, :boolean, default: false, null: false

    add_column :cart_items, :service_late_fee_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :reserva_services, :service_late_fee_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
  end
end
