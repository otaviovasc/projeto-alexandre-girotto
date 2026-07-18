class AddGuestEmailToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :guest_email, :string
  end
end
