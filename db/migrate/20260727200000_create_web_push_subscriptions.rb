class CreateWebPushSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :web_push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.text :p256dh, null: false
      t.text :auth, null: false
      t.text :user_agent
      t.boolean :active, null: false, default: true
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :web_push_subscriptions, :endpoint, unique: true
    add_index :web_push_subscriptions, [:user_id, :active]
  end
end
