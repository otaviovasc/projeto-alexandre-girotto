class AddPaymentStatusToReserva < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :payment_status, :string
  end
end
