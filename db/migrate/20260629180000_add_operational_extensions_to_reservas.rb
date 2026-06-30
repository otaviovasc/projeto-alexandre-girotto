class AddOperationalExtensionsToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :early_checkin, :boolean, default: false, null: false
    add_column :reservas, :late_checkout, :boolean, default: false, null: false
  end
end
