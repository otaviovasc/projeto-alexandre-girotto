class CreateCabanas < ActiveRecord::Migration[7.0]
  def change
    create_table :cabanas do |t|
      t.string :name
      t.references :filial, null: false, foreign_key: true
      t.decimal :price

      t.timestamps
    end
  end
end
