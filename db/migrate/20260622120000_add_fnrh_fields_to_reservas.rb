class AddFnrhFieldsToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :fnrh_status, :string, default: 'not_eligible', null: false
    add_column :reservas, :fnrh_reservation_id, :string
    add_column :reservas, :fnrh_precheckin_url, :text
    add_column :reservas, :fnrh_adults, :integer, default: 1, null: false
    add_column :reservas, :fnrh_minors, :integer, default: 0, null: false
    add_column :reservas, :fnrh_scheduled_checkin_at, :datetime
    add_column :reservas, :fnrh_precheckin_at, :datetime
    add_column :reservas, :fnrh_checkin_at, :datetime
    add_column :reservas, :fnrh_checkout_at, :datetime
    add_column :reservas, :fnrh_cancelled_at, :datetime
    add_column :reservas, :fnrh_no_show_at, :datetime
    add_column :reservas, :fnrh_synced_at, :datetime
    add_column :reservas, :fnrh_last_error, :text

    add_index :reservas, :fnrh_status
    add_index :reservas, :fnrh_reservation_id, unique: true
    add_index :reservas, :fnrh_scheduled_checkin_at
  end
end
