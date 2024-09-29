class UserMailer < ApplicationMailer
  default from: 'contato@villaggiogirotto.com.br'

  def welcome_email(user, generated_password)
    @user = user
    @password = generated_password
    @url  = 'localhost:3000/users/sign_in'
    mail(to: @user.email, subject: 'Sua hospedagem - Villagio')
  end
end
