class UserMailer < ApplicationMailer
  default from: 'Villaggio Girotto <contato@villaggiogirotto.com.br>'

  def welcome_email(user = nil, generated_password = nil)
    @user = user || params[:user]
    @password = generated_password || params[:generated_password]
    @url  = 'https://www.villaggiogirotto.com.br/users/sign_in'
    mail(to: @user.email, subject: 'Sua hospedagem - Villaggio')
  end

  def reserva_created(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/reservas/#{reserva.id}"
    @services = reserva.services.includes(:reserva_services)
    mail(to: @user.email, subject: 'Aguardando Pagamento - Villaggio')
  end

  def reserva_paid(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/reservas/#{reserva.id}"
    @services = reserva.services.includes(:reserva_services)
    mail(to: @user.email, subject: 'Pagamento Confirmado - Villaggio')
  end

  def notify_adm(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/admin/reservas_summary"
    mail(to: 'contato@villaggiogirotto.com.br', subject: "Reserva: #{reserva.payment_status} - Villaggio")
  end

  def public_booking_confirmed(user, reserva)
    return if EmailAutomationSetting.enabled?

    @user = user
    @reserva = reserva
    @reserva_payment = reserva.reserva_payments.to_a.find(&:public_booking?) ||
                       reserva.reserva_payments.order(paid_at: :desc).first
    @services = reserva.reserva_services
                       .includes(:service)
                       .where(payment_order_code: @reserva_payment&.payment_order_code)
                       .order(:service_date, :id)
    host = ENV['APP_HOST'].presence || ENV['RENDER_EXTERNAL_HOSTNAME'].presence || 'villaggio-stock.onrender.com'
    @url = "https://#{host.sub(%r{\Ahttps?://}, '')}/reserva-online-teste/confirmacao/#{@reserva_payment&.terms_token}"

    mail(to: @user.email, subject: "Reserva confirmada ##{@reserva.id} - Villaggio Girotto")
  end

  def reservation_automation(delivery)
    @delivery = delivery
    @reserva = delivery.reserva
    @body = delivery.body

    mail(to: delivery.recipient_email, subject: delivery.subject)
  end
end
