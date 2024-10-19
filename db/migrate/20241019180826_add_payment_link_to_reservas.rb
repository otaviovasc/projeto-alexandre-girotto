class AddPaymentLinkToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :payment_link_id, :string
    add_column :reservas, :payment_link_url, :string
  end
end
