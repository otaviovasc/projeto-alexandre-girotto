class AddPartnershipCreatorToReservas < ActiveRecord::Migration[7.0]
  def change
    add_reference :reservas, :partnership_creator, foreign_key: { to_table: :users }
  end
end
