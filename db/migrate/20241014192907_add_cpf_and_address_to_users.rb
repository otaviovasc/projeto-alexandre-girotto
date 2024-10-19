class AddCpfAndAddressToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :cpf, :string
    add_column :users, :state, :string
    add_column :users, :city, :string
    add_column :users, :neighborhood, :string
    add_column :users, :street, :string
    add_column :users, :street_number, :string
    add_column :users, :zipcode, :string
  end
end
