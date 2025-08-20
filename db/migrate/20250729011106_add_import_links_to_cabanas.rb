class AddImportLinksToCabanas < ActiveRecord::Migration[7.0]
  def change
    add_column :cabanas, :import_links, :text
  end
end
