require 'rufus-scheduler'

return if defined?(Rails::Console) || File.split($PROGRAM_NAME).last == 'rake' || Rails.env.test?

scheduler = Rufus::Scheduler.singleton

scheduler.every '10m' do
  Rails.logger.info "⏱️ Iniciando importação automática de reservas..."
  begin
    ImportadorDeReservasJob.run
  rescue => e
    Rails.logger.error "Erro no scheduler: #{e.message}"
  end
end
