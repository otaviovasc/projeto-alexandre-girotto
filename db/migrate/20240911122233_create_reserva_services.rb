class CreateReservaServices < ActiveRecord::Migration[7.0]
  def change
    create_table :reserva_services do |t|
      t.references :reserva, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true
      t.integer :quantity

      t.timestamps
    end
  end
end
