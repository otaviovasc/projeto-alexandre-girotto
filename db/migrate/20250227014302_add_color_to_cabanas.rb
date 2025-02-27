class AddColorToCabanas < ActiveRecord::Migration[7.0]
  def change
    add_column :cabanas, :color, :string, default: '#000000'
  end
end
