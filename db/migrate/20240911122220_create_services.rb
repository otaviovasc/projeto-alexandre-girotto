class CreateServices < ActiveRecord::Migration[7.0]
  def change
    create_table :services do |t|
      t.string :name
      t.text :description
      t.decimal :price
      t.string :duration
      t.time :start_time
      t.time :end_time
      t.references :filial, null: false, foreign_key: true

      t.timestamps
    end
  end
end
