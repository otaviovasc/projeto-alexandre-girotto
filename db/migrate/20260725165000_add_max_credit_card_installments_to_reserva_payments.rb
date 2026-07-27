class AddMaxCreditCardInstallmentsToReservaPayments < ActiveRecord::Migration[7.0]
  def change
    add_column :reserva_payments, :max_credit_card_installments, :integer, default: 6, null: false
  end
end
