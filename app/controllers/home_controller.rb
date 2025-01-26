class HomeController < ApplicationController
  layout "clientside"
  skip_before_action :authenticate_user!, only: [:root, :create_mailer_entry, :about, :experiencias, :sustentabilidade]

  def index
    @funil_mailer = FunilMailer.new
    @reservas = current_user.reservas
    @reservas.each do |reserva|
      if reserva.expired? && (reserva.waiting_payment? || reserva.pending?)
        reserva.update_column(:payment_status, 'canceled')
      end
    end
  end

  def root
    @funil_mailer = FunilMailer.new
  end

  def create_mailer_entry
    existing_mailer = FunilMailer.find_by(email: funil_mailer_params[:email])

    if existing_mailer
      flash[:notice] = "Email já registrado."
    else
      @funil_mailer = FunilMailer.new(funil_mailer_params)

      if @funil_mailer.save
        flash[:notice] = "Obrigado! Você receberá nossas ofertas a partir de agora."
      else
        flash[:alert] = "Houve um erro tentando cadastrar, tente novamente."
      end
    end

    redirect_to root_path
  end

  def about
    @funil_mailer = FunilMailer.new
  end

  def experiencias
    @funil_mailer = FunilMailer.new
  end

  def sustentabilidade
    @funil_mailer = FunilMailer.new
  end

  private

  def funil_mailer_params
    params.require(:funil_mailer).permit(:fullname, :number, :email)
  end
end
