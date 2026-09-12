class CreateGuestPortalEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :guest_portal_events do |t|
      t.references :reserva, null: false, foreign_key: true
      t.string :event_name, null: false
      t.datetime :occurred_at, null: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :guest_portal_events, [:event_name, :occurred_at]
    add_index :guest_portal_events,
              [:reserva_id, :event_name, :occurred_at],
              name: "index_guest_portal_events_on_reserva_event_time"
  end
end
