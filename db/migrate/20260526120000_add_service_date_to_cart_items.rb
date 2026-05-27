class AddServiceDateToCartItems < ActiveRecord::Migration[7.0]
  def change
    add_column :cart_items, :service_date, :date
  end
end
