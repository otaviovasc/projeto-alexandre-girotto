class AddPaymentExpiresAtToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :payment_expires_at, :datetime
  end
end
