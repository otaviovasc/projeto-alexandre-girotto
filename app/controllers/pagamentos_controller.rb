class PagamentosController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:webhook]
  skip_before_action :authenticate_user!, only: [:webhook]

  def webhook
    event = JSON.parse(request.body.read)

    # Find the Reserva based on the payment link ID from the webhook event
    reserva = Reserva.find_by(payment_link_id: event['data']['code'])  # Access the payment link code from the 'data' object

    if reserva
      # Extract the payment status from the 'data' object
      payment_status = event['data']['status']

      # Check the status of the payment
      puts "Payment status: #{payment_status}"

      case payment_status
      when 'paid'
        reserva.update_column(:payment_status, 'paid')
        # Additional actions after payment confirmation, like sending a notification
      when 'refused'
        reserva.update_column(:payment_status, 'refused')
      when 'pending'
        reserva.update_column(:payment_status, 'pending')
      end
    end

    head :ok
  rescue => e
    Rails.logger.error("Error processing webhook: #{e.message}")
    head :bad_request
  end

end
