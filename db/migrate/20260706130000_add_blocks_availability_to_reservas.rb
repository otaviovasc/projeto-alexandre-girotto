class AddBlocksAvailabilityToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :blocks_availability, :boolean, default: true, null: false
    add_index :reservas, [:cabana_id, :blocks_availability], name: 'index_reservas_on_cabana_and_availability'
  end
end
