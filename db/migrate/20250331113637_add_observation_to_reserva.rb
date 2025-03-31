class AddObservationToReserva < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :observation, :text
  end
end
