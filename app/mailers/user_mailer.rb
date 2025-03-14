class UserMailer < ApplicationMailer
  default from: 'contato@villaggiogirotto.com.br'

  def welcome_email(user, generated_password)
    @user = user
    @password = generated_password
    @url  = 'https://www.villaggiogirotto.com.br/users/sign_in'
    mail(to: @user.email, subject: 'Sua hospedagem - Villagio')
  end

  def reserva_created(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/reservas/#{reserva.id}"
    @services = reserva.services.includes(:reserva_services)
    mail(to: @user.email, subject: 'Aguardando Pagamento - Villagio')
  end

  def reserva_paid(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/reservas/#{reserva.id}"
    @services = reserva.services.includes(:reserva_services)
    mail(to: @user.email, subject: 'Pagamento Confirmado - Villagio')
  end

  def notify_adm(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/admin/reservas_summary"
    mail(to: 'otaviocavasc2@gmail.com', subject: "Reserva: #{reserva.payment_status} - Villagio")
  end
end
