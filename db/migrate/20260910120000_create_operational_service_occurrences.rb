class CreateOperationalServiceOccurrences < ActiveRecord::Migration[7.0]
  def change
    create_table :operational_service_occurrences do |t|
      t.references :cabana, null: false, foreign_key: true
      t.references :filial, null: false, foreign_key: true
      t.string :stable_id, null: false
      t.string :kind, null: false, default: 'fake_holmy_cleaning'
      t.string :event_type, null: false
      t.string :name, null: false
      t.date :service_date, null: false
      t.string :status, null: false, default: 'active'
      t.datetime :cancelled_at
      t.text :cancellation_reason

      t.timestamps
    end

    add_index :operational_service_occurrences, :stable_id, unique: true
    add_index :operational_service_occurrences, [:kind, :status, :service_date], name: 'index_operational_services_on_kind_status_date'
    add_index :operational_service_occurrences, [:cabana_id, :service_date], name: 'index_operational_services_on_cabana_date'
  end
end
