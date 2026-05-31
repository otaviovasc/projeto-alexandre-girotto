class AddManualDateOverrideToReservaServices < ActiveRecord::Migration[7.0]
  def change
    add_column :reserva_services, :manual_date_override, :boolean, default: false, null: false
  end
end
