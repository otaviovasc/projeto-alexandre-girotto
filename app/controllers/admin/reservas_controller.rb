class Admin::ReservasController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_reserva, only: [:edit, :update, :destroy, :show]

  def index
    @reservas = Reserva.all
  end

  def new
    @reserva = Reserva.new
  end

  def create
    if params[:create_user] == "true"
      # Criação de um novo usuário
      generated_password = SecureRandom.alphanumeric(8)
      @user = User.new(user_params.merge(password: generated_password, password_confirmation: generated_password))

      if @user.save
        @reserva = Reserva.new(reserva_params.merge(user_id: @user.id))
      else
        flash[:alert] = "Não foi possível criar o usuário. Verifique os dados informados."
        render :new and return
      end
    elsif params[:reserva][:user_id].present?
      # Seleção de um usuário existente
      @user = User.find_by(id: params[:reserva][:user_id])
      unless @user
        flash[:alert] = "Usuário selecionado não encontrado."
        render :new and return
      end
      @reserva = Reserva.new(reserva_params.merge(user_id: @user.id))
    else
      flash[:alert] = "Você deve selecionar um usuário existente ou criar um novo."
      render :new and return
    end

    # Cálculo do preço total da reserva
    @reserva.total_price = @reserva.calculate_total_price
    @reserva.payment_status = "paid"

    if @reserva.save
      UserMailer.reserva_paid(@user, @reserva).deliver_now
      redirect_to admin_reservas_path, notice: 'Reserva criada com sucesso.'
    else
      flash[:alert] = "Não foi possível salvar a reserva. Verifique os dados informados."
      render :new
    end
  end


  def edit
  end

  def update
    if @reserva.update(reserva_params)
      redirect_to admin_reservas_path, notice: 'Reserva was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @reserva.destroy
    redirect_to admin_reservas_path, notice: 'Reserva was successfully deleted.'
  end

  private

  def set_reserva
    @reserva = Reserva.find(params[:id])
  end

  def reserva_params
    params.require(:reserva).permit(:start_date, :end_date, :cabana_id, :user_id)
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :name)
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
