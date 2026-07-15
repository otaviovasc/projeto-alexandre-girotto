class Admin::ReservaPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_reserva_payment, only: [:mark_paid, :regenerate, :cancel]

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

  def create
    reserva = Reserva.find(params[:reserva_id])
    payment = ReservaPendingPaymentSetup.create_extra_payment!(
      reserva: reserva,
      amount: params[:amount],
      due_at: params[:due_at]
    )

    redirect_to admin_reserva_path(reserva), notice: "#{payment.installment_number}ª parcela criada."
  rescue => e
    reserva ||= Reserva.find_by(id: params[:reserva_id])
    redirect_to(reserva.present? ? admin_reserva_path(reserva) : admin_reservas_summary_path,
                alert: "Não foi possível criar nova parcela: #{e.message}")
  end

  private

  def set_reserva_payment
    @reserva_payment = ReservaPayment.find(params[:id])
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
