class AddPagarmeApiKeyToFilials < ActiveRecord::Migration[7.0]
  def change
    add_column :filials, :pagarme_api_key, :string
  end
end
