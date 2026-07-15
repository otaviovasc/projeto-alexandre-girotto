class ReservaPaymentProcessor
  def self.call(reserva_payment:, status:, source: 'cielo')
    new(reserva_payment: reserva_payment, status: status, source: source).call
  end

  def initialize(reserva_payment:, status:, source: 'cielo')
    @reserva_payment = reserva_payment
    @reserva = reserva_payment.reserva
    @status = status.to_s
    @source = source
  end

  def call
    case @status
    when 'paid'
      mark_paid!
    when 'waiting_payment', 'pending'
      mark_waiting!
    when 'unpaid', 'refused', 'failed'
      mark_refused!
    when 'canceled', 'cancelled'
      mark_canceled!
    when 'overdue'
      mark_overdue!
    end
  end

  private

  def mark_paid!
    newly_paid = false
    reservation_confirmed = false
    reservation_was_canceled = false

    ReservaPayment.transaction do
      @reserva_payment.lock!
      newly_paid = !@reserva_payment.paid?

      @reserva_payment.update!(
        payment_status: 'paid',
        paid_at: @reserva_payment.paid_at || Time.current
      )

      if @reserva.canceled?
        Rails.logger.warn("Pagamento recebido para reserva cancelada ##{@reserva.id}; reserva nao foi reativada.")
        reservation_was_canceled = true
      elsif @reserva_payment.installment_number == 1
        reservation_confirmed = !@reserva.paid?
        confirm_reserva! unless @reserva.paid?
      else
        Rails.logger.info("Parcela futura paga para reserva ##{@reserva.id}; aguardando primeira parcela para confirmar.") unless @reserva.paid?
      end
    end

    return if reservation_was_canceled

    run_confirmed_side_effects if newly_paid && reservation_confirmed && @reserva.reload.integration_ready?
  end

  def confirm_reserva!
    @reserva.update!(
      payment_status: 'paid',
      blocks_availability: true,
      payment_expires_at: nil
    )
  end

  def run_confirmed_side_effects
    CleaningServicesAssigner.new(@reserva).call
    BreakfastServicesAssigner.new(@reserva, source: 'sistema').add_if_configured
    export_reservas_to_sheets
  end

  def mark_waiting!
    return if @reserva_payment.paid?

    @reserva_payment.update!(payment_status: 'waiting_payment')
  end

  def mark_refused!
    return if @reserva_payment.paid?

    @reserva_payment.update!(payment_status: 'refused')
    cancel_reserva!("Pagamento recusado pela Cielo.") if confirmation_payment_still_needed?
  end

  def mark_canceled!
    return if @reserva_payment.paid?

    @reserva_payment.update!(payment_status: 'canceled', canceled_at: Time.current)
    cancel_reserva!("Pagamento cancelado na Cielo.") if confirmation_payment_still_needed?
  end

  def mark_overdue!
    return if @reserva_payment.paid?

    @reserva_payment.update!(payment_status: 'overdue')
    cancel_reserva!("Primeira parcela vencida sem pagamento.") if confirmation_payment_still_needed?
  end

  def cancel_reserva!(reason)
    return if @reserva.canceled?

    @reserva.cancel_for_operations!(by: nil, reason: reason)
    export_reservas_to_sheets
  end

  def export_reservas_to_sheets
    return unless GoogleSheetsExportService.configured?

    GoogleSheetsExportService.export_reservas(
      Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
    )
  rescue => e
    Rails.logger.error("Erro ao sincronizar reserva apos pagamento #{@source}: #{e.message}")
  end

  def confirmation_payment_still_needed?
    @reserva_payment.confirmation_installment? && !@reserva.paid?
  end
end
