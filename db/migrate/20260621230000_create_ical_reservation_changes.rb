class CreateIcalReservationChanges < ActiveRecord::Migration[7.0]
  def change
    create_table :ical_reservation_changes do |t|
      t.references :reserva, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :old_uid
      t.string :new_uid
      t.date :old_start_date, null: false
      t.date :old_end_date, null: false
      t.date :new_start_date, null: false
      t.date :new_end_date, null: false
      t.datetime :acknowledged_at

      t.timestamps
    end

    add_index :ical_reservation_changes,
              [:reserva_id, :acknowledged_at],
              name: 'index_ical_changes_on_reserva_and_acknowledged'
  end
end
