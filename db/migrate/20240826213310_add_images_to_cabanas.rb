class AddImagesToCabanas < ActiveRecord::Migration[7.0]
  def change
    add_column :cabanas, :images, :json
  end
end
