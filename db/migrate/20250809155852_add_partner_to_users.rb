class AddPartnerToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :partner, :boolean
  end
end
