class UpdateUsersTable < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :cpf, :string
    remove_column :users, :state, :string
    remove_column :users, :city, :string
    remove_column :users, :neighborhood, :string
    remove_column :users, :street, :string
    remove_column :users, :street_number, :string
    remove_column :users, :zipcode, :string

    add_column :users, :telephone, :string
  end
end
