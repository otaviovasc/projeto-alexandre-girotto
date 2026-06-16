class AddObservationToCartItems < ActiveRecord::Migration[7.0]
  def change
    add_column :cart_items, :observation, :text
  end
end
