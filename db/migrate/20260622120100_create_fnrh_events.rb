class CreateFnrhEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :fnrh_events do |t|
      t.references :reserva, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :source, null: false
      t.string :status, null: false
      t.text :message
      t.jsonb :metadata, default: {}, null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :fnrh_events, [:reserva_id, :occurred_at]
  end
end
