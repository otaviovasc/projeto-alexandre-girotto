class RemoveImagesFromCabanas < ActiveRecord::Migration[7.0]
  def change
    remove_column :cabanas, :images, :json
  end
end
