class CreateFilials < ActiveRecord::Migration[7.0]
  def change
    create_table :filials do |t|
      t.string :name

      t.timestamps
    end
  end
end
