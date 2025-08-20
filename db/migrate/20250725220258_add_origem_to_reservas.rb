class AddOrigemToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :origem, :string
  end
end
