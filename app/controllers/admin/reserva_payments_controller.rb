class Admin::ReservaPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_reserva_payment, only: [:mark_paid, :regenerate, :cancel, :sync]

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
      due_at: params[:due_at],
      max_credit_card_installments: params[:max_credit_card_installments]
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

    ReservaPaymentProcessor.call(reserva_payment: @reserva_payment, status: 'canceled', source: 'manual_cancel')
    redirect_to admin_reserva_path(@reserva_payment.reserva), notice: 'Link cancelado no sistema.'
  rescue => e
    redirect_to admin_reserva_path(@reserva_payment.reserva), alert: "Não foi possível cancelar o link: #{e.message}"
  end

  def sync
    result = CieloPendingPaymentSync.sync_order_code(
      order_code: @reserva_payment.payment_order_code,
      filial: @reserva_payment.reserva.cabana.filial
    )

    redirect_to admin_reserva_path(@reserva_payment.reserva), sync_flash_for(result)
  rescue => e
    redirect_to admin_reserva_path(@reserva_payment.reserva), alert: "Não foi possível conferir na Cielo: #{e.message}"
  end

  def create
    reserva = Reserva.find(params[:reserva_id])
    payment = ReservaPendingPaymentSetup.create_extra_payment!(
      reserva: reserva,
      amount: params[:amount],
      due_at: params[:due_at],
      max_credit_card_installments: params[:max_credit_card_installments]
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

  def sync_flash_for(result)
    if result.paid.positive?
      { notice: 'Pagamento confirmado na Cielo e aplicado no sistema.' }
    elsif result.respond_to?(:late_paid) && result.late_paid.positive?
      { alert: 'A Cielo informou pagamento após o vencimento. A reserva não foi reativada automaticamente.' }
    elsif result.refused.positive?
      { alert: 'A Cielo informou pagamento recusado.' }
    elsif result.canceled.positive?
      { alert: 'A Cielo informou pagamento cancelado.' }
    elsif result.errors.positive?
      { alert: 'A Cielo ainda não retornou esse pagamento. Tente novamente em alguns minutos.' }
    else
      { notice: 'A Cielo ainda mostra este pagamento como aguardando.' }
    end
  end
end
