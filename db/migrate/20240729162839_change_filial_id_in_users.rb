class ChangeFilialIdInUsers < ActiveRecord::Migration[7.0]
  def change
    change_column_null :users, :filial_id, true
  end
end
