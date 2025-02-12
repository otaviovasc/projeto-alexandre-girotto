class AddUniqueIndexToUsersTelephone < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :telephone, unique: true
  end
end
