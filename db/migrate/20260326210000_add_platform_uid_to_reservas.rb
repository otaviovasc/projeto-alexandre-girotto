class AddPlatformUidToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :platform_uid, :string
    add_index :reservas, [:cabana_id, :platform_uid], name: "index_reservas_on_cabana_id_and_platform_uid"
  end
end
