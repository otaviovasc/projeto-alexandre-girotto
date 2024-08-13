class CreateReservas < ActiveRecord::Migration[7.0]
  def change
    create_table :reservas do |t|
      t.date :start_date
      t.date :end_date
      t.references :cabana, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.decimal :total_price

      t.timestamps
    end
  end
end
