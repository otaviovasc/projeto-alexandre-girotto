class AddShowInMarketplaceToServices < ActiveRecord::Migration[7.0]
  def change
    add_column :services, :show_in_marketplace, :boolean
  end
end
