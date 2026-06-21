class AddServicePurchaseOverrideToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :service_purchase_override, :boolean, default: false, null: false
  end
end
