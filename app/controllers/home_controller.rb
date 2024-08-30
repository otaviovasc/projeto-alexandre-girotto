class HomeController < ApplicationController
  layout "clientside"
  skip_before_action :authenticate_user!, only: [:root]

  def root
  end

  def create_mailer_entry
    @funil_mailer = FunilMailer.new(funil_mailer_params)

    if @funil_mailer.save
      flash[:notice] = "Obrigado! Você recerá nossas ofertas a partir de agora."
    else
      flash[:alert] = "Houve um erro tentando cadastrar, tente novamente"
    end
  end

  def index
  end

  private

  def funil_mailer_params
    params.require(:funil_mailer).permit(:fullname, :number, :email)
  end
end
