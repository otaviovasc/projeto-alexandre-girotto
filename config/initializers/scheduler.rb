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
    result = ReservationEmailDispatcher.run(exclude_trigger_key: 'reservation_confirmed')
    Rails.logger.info(
      "Disparos de e-mails concluídos: #{result.checked} verificados, " \
      "#{result.sent} enviados, #{result.skipped} ignorados, #{result.failed} falhas."
    )
  rescue => e
    Rails.logger.error "Erro nos disparos de e-mails de reservas: #{e.message}"
  end
end

scheduler.every '3m', first_in: '1m', overlap: false do
  next unless EmailAutomationSetting.enabled?

  Rails.logger.info 'Iniciando disparos rápidos de confirmação de reserva...'
  begin
    result = ReservationEmailDispatcher.run(limit: 20, trigger_key: 'reservation_confirmed')
    Rails.logger.info(
      "Confirmações de reserva concluídas: #{result.checked} verificados, " \
      "#{result.sent} enviados, #{result.skipped} ignorados, #{result.failed} falhas."
    )
  rescue => e
    Rails.logger.error "Erro nos disparos rápidos de confirmação de reserva: #{e.message}"
  end
end

scheduler.cron '5 0 * * * America/Sao_Paulo', overlap: false do
  next unless EmailAutomationSetting.enabled?

  Rails.logger.info 'Preparando mensagens de WhatsApp do dia...'
  begin
    result = ReservationWhatsappTaskMaterializer.run
    Rails.logger.info(
      "Mensagens WhatsApp preparadas: #{result.checked} verificadas, " \
      "#{result.created} criadas, #{result.updated} atualizadas."
    )
  rescue => e
    Rails.logger.error "Erro ao preparar mensagens WhatsApp: #{e.message}"
  end
end

scheduler.cron '0 7 * * * America/Sao_Paulo', overlap: false do
  next unless EmailAutomationSetting.enabled?

  Rails.logger.info 'Conferindo lembrete de WhatsApp das 7h...'
  begin
    result = ReservationWhatsappTaskReminder.run(slot: :morning)
    result.messages.each { |message| Rails.logger.warn(message) }
    Rails.logger.info(
      "Push WhatsApp 7h: #{result.push_sent} enviado(s), " \
      "#{result.push_failed} falha(s)."
    )
  rescue => e
    Rails.logger.error "Erro no lembrete de WhatsApp das 7h: #{e.message}"
  end
end

scheduler.cron '0 18 * * * America/Sao_Paulo', overlap: false do
  next unless EmailAutomationSetting.enabled?

  Rails.logger.info 'Conferindo lembrete de WhatsApp das 18h...'
  begin
    result = ReservationWhatsappTaskReminder.run(slot: :evening)
    result.messages.each { |message| Rails.logger.warn(message) }
    Rails.logger.info(
      "Push WhatsApp 18h: #{result.push_sent} enviado(s), " \
      "#{result.push_failed} falha(s)."
    )
  rescue => e
    Rails.logger.error "Erro no lembrete de WhatsApp das 18h: #{e.message}"
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
