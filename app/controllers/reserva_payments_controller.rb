class ReservaPaymentsController < ApplicationController
  layout 'fnrh_portal'

  skip_before_action :authenticate_user!
  before_action :set_reserva_payment

  def show
    @reserva = @reserva_payment.reserva
    sync_cielo_checkout_status!
    @reserva_payment.reload
    @reserva = @reserva_payment.reserva
  end

  def accept_terms
    @reserva = @reserva_payment.reserva

    unless ActiveModel::Type::Boolean.new.cast(params[:terms_accepted])
      flash.now[:alert] = 'Confirme o aceite dos termos para continuar.'
      render :show, status: :unprocessable_entity
      return
    end

    name = params[:terms_acceptance_name].to_s.squish
    if name.split(/\s+/).size < 2
      flash.now[:alert] = 'Informe nome e sobrenome do responsável pela reserva.'
      render :show, status: :unprocessable_entity
      return
    end

    @reserva_payment.update!(
      terms_accepted_at: Time.current,
      terms_acceptance_name: name,
      terms_acceptance_ip: request.remote_ip,
      terms_acceptance_user_agent: request.user_agent
    )

    redirect_to reserva_payment_path(token: @reserva_payment.terms_token), notice: 'Termos aceitos. Você já pode seguir para o pagamento.'
  end

  private

  def set_reserva_payment
    @reserva_payment = ReservaPayment.includes(reserva: [:user, { cabana: :filial }]).find_by!(terms_token: params[:token])
  end

  def sync_cielo_checkout_status!
    return unless @reserva_payment.waiting_payment?
    return if @reserva_payment.payment_order_code.blank?

    filial = @reserva_payment.reserva.cabana.filial
    transaction = CieloCheckoutService::TransactionQuery.new(
      client_id: filial.cielo_checkout_client_id_for_payments,
      client_secret: filial.cielo_checkout_client_secret_for_payments
    ).find_by_order_number(@reserva_payment.payment_order_code)

    status = CieloCheckoutService.payment_status_from_transaction(transaction)
    return if status.blank?

    checkout_order_number = transaction['checkoutOrderNumber'].presence || @reserva_payment.payment_link_id
    remember_cielo_checkout_order_number(checkout_order_number)

    PaymentStatusProcessor.call(
      identifiers: [@reserva_payment.payment_order_code, @reserva_payment.payment_link_id, checkout_order_number],
      status: status
    )
  rescue CieloCheckoutService::Error => e
    Rails.logger.warn("Unable to sync Cielo Checkout reservation payment status: #{e.message}")
  end

  def remember_cielo_checkout_order_number(checkout_order_number)
    return if checkout_order_number.blank?
    return if @reserva_payment.payment_link_id == checkout_order_number

    @reserva_payment.update_columns(
      payment_link_id: checkout_order_number,
      updated_at: Time.current
    )
  end
end
