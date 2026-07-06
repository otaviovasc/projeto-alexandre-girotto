class AddServiceMaxInstallmentsToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :service_max_installments, :integer, default: 1, null: false
  end
end
