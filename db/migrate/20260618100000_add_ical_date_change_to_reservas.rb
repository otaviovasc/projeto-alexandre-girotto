class AddIcalDateChangeToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :ical_date_change_since, :datetime
    add_index :reservas, :ical_date_change_since
  end
end
