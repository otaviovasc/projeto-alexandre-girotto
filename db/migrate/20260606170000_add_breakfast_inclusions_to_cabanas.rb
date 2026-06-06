class AddBreakfastInclusionsToCabanas < ActiveRecord::Migration[7.0]
  def change
    add_column :cabanas, :breakfast_included_airbnb, :boolean, default: false, null: false
    add_column :cabanas, :breakfast_included_booking, :boolean, default: false, null: false
    add_column :cabanas, :breakfast_included_holmy, :boolean, default: false, null: false
    add_column :cabanas, :breakfast_included_direct, :boolean, default: false, null: false

    add_column :reservas, :breakfast_manual_override, :boolean, default: false, null: false
  end
end
