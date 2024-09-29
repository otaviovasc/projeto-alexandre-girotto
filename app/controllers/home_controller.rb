class HomeController < ApplicationController
  layout "clientside"
  skip_before_action :authenticate_user!, only: [:root, :create_mailer_entry, :about, :experiencias, :sustentabilidade]

  def root
    @funil_mailer = FunilMailer.new
  end
  def index
    @funil_mailer = FunilMailer.new
  end

  def create_mailer_entry
    @funil_mailer = FunilMailer.new(funil_mailer_params)

    if @funil_mailer.save
      flash[:notice] = "Obrigado! Você recerá nossas ofertas a partir de agora."
    else
      if @funil_mailer.errors[:email].include?("has already been taken")
        flash[:notice] = "Email já registrado."
      else
        flash[:alert] = "Houve um erro tentando cadastrar, tente novamente"
      end
    end
  end


  def about
  end

  def experiencias
  end

  def sustentabilidade
  end
  
  private

  def funil_mailer_params
    params.require(:funil_mailer).permit(:fullname, :number, :email)
  end
end
