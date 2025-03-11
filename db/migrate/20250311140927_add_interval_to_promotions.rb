class AddIntervalToPromotions < ActiveRecord::Migration[7.0]
  def change
    add_column :promotions, :start_date, :date
    add_column :promotions, :end_date, :date
  end
end
