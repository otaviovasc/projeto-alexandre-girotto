class ChangeItemAndServiceNullInCartItems < ActiveRecord::Migration[7.0]
  def change
    change_column_null :cart_items, :item_id, true
    change_column_null :cart_items, :service_id, true
  end
end
