class AddPublicBookingPayloadToReservaPayments < ActiveRecord::Migration[7.0]
  def change
    add_column :reserva_payments, :public_booking_payload, :jsonb, default: {}, null: false
  end
end
