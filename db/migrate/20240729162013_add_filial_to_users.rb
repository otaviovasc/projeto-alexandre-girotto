class AddFilialToUsers < ActiveRecord::Migration[7.0]
  def change
    add_reference :users, :filial, null: false, foreign_key: true
  end
end
