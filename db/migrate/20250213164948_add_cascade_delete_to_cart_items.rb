class AddCascadeDeleteToCartItems < ActiveRecord::Migration[7.0]
  def change
    remove_foreign_key :cart_items, :reservas
    add_foreign_key :cart_items, :reservas, on_delete: :cascade
  end
end
