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
    if late_or_inactive_reservation_payment?
      Rails.logger.warn(
        "Pagamento recebido depois do prazo ou em link inativo para reserva_payment ##{@reserva_payment.id}; " \
        "reserva nao foi confirmada."
      )
      mark_late_paid!
      return
    end

    if inactive_payment_without_manual_override?
      Rails.logger.warn("Pagamento recebido para link inativo de reserva_payment ##{@reserva_payment.id}; reserva nao foi alterada.")
      return
    end

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
    created_public_booking_services = PublicBookingServicesMaterializer.call(@reserva_payment)
    CleaningServicesAssigner.new(@reserva).call
    BreakfastServicesAssigner.new(@reserva, source: 'sistema').add_if_configured
    export_service_purchases_to_sheets(created_public_booking_services)
    send_public_booking_confirmation_email
    export_reservas_to_sheets
  end

  def mark_waiting!
    return if payment_finalized?

    @reserva_payment.update!(payment_status: 'waiting_payment')
  end

  def mark_refused!
    return if payment_finalized?

    @reserva_payment.update!(payment_status: 'refused')
    cancel_reserva!("Pagamento recusado pela Cielo.") if confirmation_payment_still_needed?
  end

  def mark_canceled!
    return if payment_finalized?
    return if @reserva_payment.canceled? || @reserva_payment.overdue?

    cancel_cielo_link

    @reserva_payment.reload
    return if payment_finalized?
    @reserva_payment.update!(payment_status: 'canceled', canceled_at: Time.current)
    cancel_reserva!("Pagamento cancelado na Cielo.") if confirmation_payment_still_needed?
  end

  def mark_overdue!
    return if payment_finalized?
    return if @reserva_payment.canceled? || @reserva_payment.overdue?

    cancel_cielo_link

    @reserva_payment.reload
    return if payment_finalized?
    @reserva_payment.update!(payment_status: 'overdue')
    cancel_reserva!("Primeira parcela vencida sem pagamento.") if confirmation_payment_still_needed?
  end

  def mark_late_paid!
    newly_late_paid = false
    canceled_reserva = false

    ReservaPayment.transaction do
      @reserva_payment.lock!
      unless @reserva_payment.paid? || @reserva_payment.late_paid?
        newly_late_paid = true
        @reserva_payment.update!(
          payment_status: 'late_paid',
          paid_at: @reserva_payment.paid_at || Time.current
        )
      end
    end

    return unless newly_late_paid

    if confirmation_payment_still_needed?
      cancel_reserva!("Pagamento recebido após vencimento; reserva não confirmada.")
      canceled_reserva = true
    end

    export_reservas_to_sheets unless canceled_reserva
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

  def export_service_purchases_to_sheets(reserva_services)
    reserva_services = Array(reserva_services).compact
    return if reserva_services.empty? || !GoogleSheetsExportService.configured?

    result = GoogleSheetsExportService.export_service_purchases(reserva_services)
    Rails.logger.warn("Google Sheets service purchases export failed: #{result[:error]}") unless result[:success]
  rescue => e
    Rails.logger.error("Google Sheets service purchases export error: #{e.message}")
  end

  def send_public_booking_confirmation_email
    return unless @reserva_payment.public_booking?
    return if @reserva.user.email.blank?

    UserMailer.public_booking_confirmed(@reserva.user, @reserva).deliver_later
  rescue => e
    Rails.logger.error("Erro ao enviar email da reserva publica ##{@reserva.id}: #{e.message}")
  end

  def confirmation_payment_still_needed?
    @reserva_payment.confirmation_installment? && !@reserva.paid?
  end

  def payment_finalized?
    @reserva_payment.paid? || @reserva_payment.late_paid?
  end

  def late_or_inactive_reservation_payment?
    return false if @source.to_s == 'manual'

    deadline_passed = @reserva_payment.due_at.present? && @reserva_payment.due_at < Time.current
    link_inactive = @reserva_payment.canceled? || @reserva_payment.overdue? || @reserva_payment.refused?
    reservation_inactive = @reserva.canceled? && !@reserva_payment.paid?

    deadline_passed || link_inactive || reservation_inactive
  end

  def inactive_payment_without_manual_override?
    return @reserva_payment.canceled? || @reserva_payment.late_paid? if @source.to_s == 'manual'

    @reserva_payment.canceled? || @reserva_payment.overdue? || @reserva_payment.refused? || @reserva_payment.late_paid?
  end

  def cancel_cielo_link
    return if @source.to_s == 'cielo_cancel_guard'

    CieloCheckoutLinkCanceller.call(reserva_payment: @reserva_payment, source: @source)
  end
end
