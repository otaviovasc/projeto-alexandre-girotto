class AddCriticalStockToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :critical_stock, :integer
  end
end
