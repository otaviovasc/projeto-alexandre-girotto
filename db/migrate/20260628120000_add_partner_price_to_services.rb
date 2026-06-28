class AddPartnerPriceToServices < ActiveRecord::Migration[7.0]
  def up
    add_column :services, :partner_price, :decimal
    execute "UPDATE services SET partner_price = COALESCE(price, 0)"
    change_column_null :services, :partner_price, false
  end

  def down
    remove_column :services, :partner_price
  end
end
