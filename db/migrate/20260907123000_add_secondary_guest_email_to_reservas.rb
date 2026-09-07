class AddSecondaryGuestEmailToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :guest_email_secondary, :string

    remove_index :reservation_email_deliveries,
                 name: 'idx_reservation_email_deliveries_unique_template',
                 if_exists: true
    add_index :reservation_email_deliveries,
              [:reserva_id, :reservation_email_template_id, :recipient_email],
              unique: true,
              name: 'idx_reservation_email_deliveries_unique_recipient'
  end
end
