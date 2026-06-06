class AddGroupCreatedToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :group_created, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        execute "UPDATE reservas SET group_created = TRUE"
      end
    end
  end
end
