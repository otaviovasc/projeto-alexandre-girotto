class AddCancellationFieldsToReservas < ActiveRecord::Migration[7.0]
  def change
    add_column :reservas, :canceled_at, :datetime
    add_column :reservas, :cancellation_reason, :text
    add_reference :reservas, :canceled_by, foreign_key: { to_table: :users }
  end
end
