class CreateReservationWhatsappTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :reservation_whatsapp_tasks do |t|
      t.references :reserva, null: false, foreign_key: true
      t.references :reservation_email_template,
                   foreign_key: true,
                   index: { name: 'idx_reservation_whatsapp_tasks_on_template_id' }
      t.string :trigger_key, null: false
      t.string :template_name, null: false
      t.text :message_body, null: false
      t.datetime :scheduled_at, null: false
      t.date :scheduled_on, null: false
      t.datetime :completed_at
      t.date :morning_notified_on
      t.date :evening_notified_on

      t.timestamps
    end

    add_index :reservation_whatsapp_tasks, :trigger_key
    add_index :reservation_whatsapp_tasks, :scheduled_on
    add_index :reservation_whatsapp_tasks, :completed_at
    add_index :reservation_whatsapp_tasks,
              [:reserva_id, :reservation_email_template_id],
              unique: true,
              name: 'idx_reservation_whatsapp_tasks_unique_template'
  end
end
