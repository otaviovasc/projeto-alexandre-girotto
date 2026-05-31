class AddIcalTrackingToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :ical_uid, :string
    add_column :reservas, :imported_start_date, :date
    add_column :reservas, :imported_end_date, :date
    add_column :reservas, :manual_override, :boolean, null: false, default: false
    add_column :reservas, :ical_uid_from_feed, :boolean, null: false, default: false
    add_column :reservas, :ical_missing_since, :datetime

    add_index :reservas, [:cabana_id, :origem, :ical_uid], name: "index_reservas_on_imported_ical"
    add_index :reservas, :ical_missing_since
  end
end
