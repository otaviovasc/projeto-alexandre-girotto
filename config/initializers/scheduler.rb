require 'rufus-scheduler'

return if defined?(Rails::Console) || File.split($PROGRAM_NAME).last == 'rake' || Rails.env.test?

scheduler = Rufus::Scheduler.singleton

scheduler.every '10m', overlap: false do
  Rails.logger.info "⏱️ Iniciando importação automática de reservas..."
  begin
    ImportadorDeReservasJob.run
  rescue => e
    Rails.logger.error "Erro no scheduler: #{e.message}"
  end
end

scheduler.every '5m', overlap: false do
  next unless Fnrh::Configuration.enabled?

  Rails.logger.info 'Iniciando automações da FNRH...'
  begin
    Fnrh::AutomationJob.run
  rescue => e
    Rails.logger.error "Erro nas automações da FNRH: #{e.message}"
  end
end

scheduler.every '30m', first_in: '3m', overlap: false do
  next unless ServicePaymentProvider.cielo_checkout?

  Rails.logger.info 'Iniciando conferência de pagamentos pendentes da Cielo...'
  begin
    result = CieloPendingPaymentSync.run
    expiry_result = ReservaPaymentExpiry.run
    Rails.logger.info(
      "Conferência Cielo concluída: #{result.checked} verificados, " \
      "#{result.paid} pagos, #{result.refused} recusados, " \
      "#{result.canceled} cancelados, #{result.errors} erros. " \
      "#{expiry_result.expired} parcela(s) vencida(s) de reserva."
    )
  rescue => e
    Rails.logger.error "Erro na conferência de pagamentos pendentes da Cielo: #{e.message}"
  end
end

scheduler.every '30m', first_in: '8m', overlap: false do
  next unless EmailAutomationSetting.enabled?

  Rails.logger.info 'Iniciando disparos de e-mails de reservas...'
  begin
    result = ReservationEmailDispatcher.run
    Rails.logger.info(
      "Disparos de e-mails concluídos: #{result.checked} verificados, " \
      "#{result.sent} enviados, #{result.skipped} ignorados, #{result.failed} falhas."
    )
  rescue => e
    Rails.logger.error "Erro nos disparos de e-mails de reservas: #{e.message}"
  end
end

scheduler.every '1d', first_in: '15m', overlap: false do
  Rails.logger.info 'Limpando PDFs antigos de fotos impressas...'
  begin
    PhotoPrintAttachmentCleanup.run
  rescue => e
    Rails.logger.error "Erro na limpeza de fotos impressas: #{e.message}"
  end
end
