# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def pagarme_postback
    # Validate the request comes from Pagar.me
    if valid_pagarme_request?(request)
      transaction_id = params[:transaction][:id]
      status = params[:current_status]

      # Find the reservation associated with this transaction
      reserva = Reserva.find_by(transaction_id: transaction_id)

      if reserva
        # Update reservation based on the new status
        reserva.update(payment_status: status)
        head :ok
      else
        puts "Reservation not found for transaction ID: #{transaction_id}"
        head :not_found
      end
    else
      head :unauthorized
    end
  end

  private

  def valid_pagarme_request?(request)
    # Implement validation logic, e.g., verify the request's signature
    true
  end
end
