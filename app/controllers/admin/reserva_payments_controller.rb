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

  private

  def set_reserva_payment
    @reserva_payment = ReservaPayment.find(params[:id])
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
