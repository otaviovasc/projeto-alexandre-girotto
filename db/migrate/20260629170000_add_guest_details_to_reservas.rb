class AddGuestDetailsToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :guest_name, :string
    add_column :reservas, :guest_phone, :string
  end
end
