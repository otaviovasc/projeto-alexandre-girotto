class AddAddressToFilial < ActiveRecord::Migration[7.0]
  def change
    add_column :filials, :address, :string
  end
end
