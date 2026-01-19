class AddRegionToServices < ActiveRecord::Migration[7.0]
  def change
    add_column :services, :region, :string, default: 'SP'
  end
end
