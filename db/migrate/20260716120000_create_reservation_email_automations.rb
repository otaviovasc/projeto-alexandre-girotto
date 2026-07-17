class CreateReservationEmailAutomations < ActiveRecord::Migration[7.0]
  def change
    create_table :email_automation_settings do |t|
      t.boolean :enabled, null: false, default: false
      t.datetime :paused_at
      t.references :paused_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    create_table :reservation_email_templates do |t|
      t.string :name, null: false
      t.string :trigger_key, null: false
      t.string :trigger_anchor, null: false
      t.integer :offset_days, null: false, default: 0
      t.time :send_time
      t.string :filial_scope, null: false, default: 'all'
      t.string :subject, null: false
      t.text :body, null: false
      t.boolean :active, null: false, default: true
      t.boolean :system_template, null: false, default: false

      t.timestamps
    end

    create_table :reservation_email_deliveries do |t|
      t.references :reserva, null: false, foreign_key: true
      t.references :reservation_email_template,
                   foreign_key: true,
                   index: { name: 'idx_reservation_email_deliveries_on_template_id' }
      t.string :trigger_key, null: false
      t.string :recipient_email, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.string :status, null: false, default: 'pending'
      t.datetime :scheduled_at, null: false
      t.datetime :sent_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :email_automation_settings, :enabled
    add_index :reservation_email_templates, :trigger_key, unique: true
    add_index :reservation_email_templates, :filial_scope
    add_index :reservation_email_templates, :active
    add_index :reservation_email_deliveries, :status
    add_index :reservation_email_deliveries, :scheduled_at
    add_index :reservation_email_deliveries,
              [:reserva_id, :reservation_email_template_id],
              unique: true,
              name: 'idx_reservation_email_deliveries_unique_template'
  end
end
