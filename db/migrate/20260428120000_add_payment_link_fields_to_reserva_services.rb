class AddPaymentLinkFieldsToReservaServices < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column :reserva_services, :payment_status, :string
    add_column :reserva_services, :payment_link_id, :string
    add_column :reserva_services, :payment_link_url, :string
    add_column :reserva_services, :payment_order_code, :string
    add_column :reserva_services, :payment_expires_at, :datetime

    add_index :reserva_services, :payment_link_id, algorithm: :concurrently
    add_index :reserva_services, :payment_order_code, algorithm: :concurrently

    add_column :cart_items, :payment_status, :string
    add_column :cart_items, :payment_link_id, :string
    add_column :cart_items, :payment_link_url, :string
    add_column :cart_items, :payment_order_code, :string
    add_column :cart_items, :payment_expires_at, :datetime

    add_index :cart_items, :payment_link_id, algorithm: :concurrently
    add_index :cart_items, :payment_order_code, algorithm: :concurrently
  end
end
