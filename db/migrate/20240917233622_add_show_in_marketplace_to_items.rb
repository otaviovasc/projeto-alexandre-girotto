class AddShowInMarketplaceToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :show_in_marketplace, :boolean
  end
end
