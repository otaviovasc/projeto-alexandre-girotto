class AddLinkGuiaToCabanas < ActiveRecord::Migration[7.0]
  def change
    add_column :cabanas, :link_guia, :string
  end
end
