class CreatePriceRules < ActiveRecord::Migration[7.0]
  def change
    create_table :price_rules do |t|
      t.references :cabana, null: false, foreign_key: true
      t.string :day_type
      t.decimal :price

      t.timestamps
    end
  end
end
