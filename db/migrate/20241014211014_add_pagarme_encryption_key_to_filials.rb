class AddPagarmeEncryptionKeyToFilials < ActiveRecord::Migration[7.0]
  def change
    add_column :filials, :pagarme_encryption_key, :string
  end
end
