class AddControlTitleToRecurringMaintenanceRules < ActiveRecord::Migration[7.0]
  def change
    add_column :recurring_maintenance_rules, :control_title, :string
  end
end
