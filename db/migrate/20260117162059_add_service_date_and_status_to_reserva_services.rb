class AddServiceDateAndStatusToReservaServices < ActiveRecord::Migration[7.0]
  def change
    add_column :reserva_services, :service_date, :date
    add_column :reserva_services, :status, :string, default: 'active'
  end
end
