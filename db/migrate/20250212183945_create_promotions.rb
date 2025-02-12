class CreatePromotions < ActiveRecord::Migration[7.0]
  def change
    create_table :promotions do |t|
      t.references :cabana, null: false, foreign_key: true
      t.date :date
      t.decimal :price

      t.timestamps
    end
  end
end
