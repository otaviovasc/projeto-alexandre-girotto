class CreateReservaPayments < ActiveRecord::Migration[7.0]
  def change
    create_table :reserva_payments do |t|
      t.references :reserva, null: false, foreign_key: true
      t.integer :installment_number, null: false, default: 1
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.datetime :due_at, null: false
      t.string :payment_status, null: false, default: 'waiting_payment'
      t.string :payment_order_code
      t.string :payment_link_id
      t.text :payment_link_url
      t.string :terms_token, null: false
      t.datetime :terms_accepted_at
      t.string :terms_acceptance_name
      t.string :terms_acceptance_ip
      t.text :terms_acceptance_user_agent
      t.datetime :paid_at
      t.datetime :canceled_at

      t.timestamps
    end

    add_index :reserva_payments, :payment_status
    add_index :reserva_payments, :due_at
    add_index :reserva_payments, :payment_order_code, unique: true
    add_index :reserva_payments, :payment_link_id
    add_index :reserva_payments, :terms_token, unique: true
  end
end
