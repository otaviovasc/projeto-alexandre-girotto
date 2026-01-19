class AddRegionToFilials < ActiveRecord::Migration[7.0]
  def change
    add_column :filials, :region, :string
  end
end
