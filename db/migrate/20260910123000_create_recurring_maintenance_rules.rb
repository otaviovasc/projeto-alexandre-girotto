class CreateRecurringMaintenanceRules < ActiveRecord::Migration[7.0]
  def change
    create_table :recurring_maintenance_rules do |t|
      t.string :title, null: false
      t.text :message_body, null: false
      t.text :recipients_text, null: false
      t.integer :frequency_interval, null: false, default: 1
      t.string :frequency_unit, null: false, default: 'monthly'
      t.date :first_due_on, null: false
      t.boolean :all_cabanas, null: false, default: false
      t.text :cabana_ids_text
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :recurring_maintenance_rules, :active
    add_index :recurring_maintenance_rules, :first_due_on

    add_reference :reservation_whatsapp_tasks,
                  :operational_service_occurrence,
                  foreign_key: true,
                  index: { name: 'idx_whatsapp_tasks_on_operational_occurrence_id' }
    add_column :reservation_whatsapp_tasks, :recipient_name, :string
    add_column :reservation_whatsapp_tasks, :recipient_phone, :string
    change_column_null :reservation_whatsapp_tasks, :reserva_id, true
    add_index :reservation_whatsapp_tasks,
              [:operational_service_occurrence_id, :trigger_key, :recipient_phone],
              unique: true,
              name: 'idx_whatsapp_tasks_unique_operational_recipient'
  end
end
