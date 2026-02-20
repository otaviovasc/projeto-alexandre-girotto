class AddObservationToReservaServices < ActiveRecord::Migration[7.0]
  def change
    add_column :reserva_services, :observation, :text
  end
end
