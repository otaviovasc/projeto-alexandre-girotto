class Admin::ReservaPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_reserva_payment

  def mark_paid
    ReservaPaymentProcessor.call(reserva_payment: @reserva_payment, status: 'paid', source: 'manual')
    redirect_to admin_reserva_path(@reserva_payment.reserva), notice: 'Parcela marcada como paga e reserva confirmada.'
  rescue => e
    redirect_to admin_reserva_path(@reserva_payment.reserva), alert: "Não foi possível marcar como paga: #{e.message}"
  end

  def regenerate
    new_payment = ReservaPendingPaymentSetup.regenerate_payment!(
      reserva_payment: @reserva_payment,
      amount: params[:amount],
      due_at: params[:due_at]
    )
    redirect_to admin_reserva_path(new_payment.reserva), notice: 'Link antigo cancelado e novo link gerado.'
  rescue => e
    redirect_to admin_reserva_path(@reserva_payment.reserva), alert: "Não foi possível gerar novo link: #{e.message}"
  end

  def cancel
    if @reserva_payment.paid?
      redirect_to admin_reserva_path(@reserva_payment.reserva), alert: 'Não é possível cancelar uma parcela já paga.'
      return
    end

    @reserva_payment.update!(payment_status: 'canceled', canceled_at: Time.current)
    redirect_to admin_reserva_path(@reserva_payment.reserva), notice: 'Link cancelado no sistema.'
  rescue => e
    redirect_to admin_reserva_path(@reserva_payment.reserva), alert: "Não foi possível cancelar o link: #{e.message}"
  end

  private

  def set_reserva_payment
    @reserva_payment = ReservaPayment.find(params[:id])
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
