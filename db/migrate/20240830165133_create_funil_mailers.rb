class CreateFunilMailers < ActiveRecord::Migration[7.0]
  def change
    create_table :funil_mailers do |t|
      t.string :fullname
      t.string :number
      t.string :email

      t.timestamps
    end
  end
end
