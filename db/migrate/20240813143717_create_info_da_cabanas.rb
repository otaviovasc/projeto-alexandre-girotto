class CreateInfoDaCabanas < ActiveRecord::Migration[7.0]
  def change
    create_table :info_da_cabanas do |t|
      t.references :cabana, null: false, foreign_key: true
      t.string :info_type
      t.string :title
      t.text :content

      t.timestamps
    end
  end
end
