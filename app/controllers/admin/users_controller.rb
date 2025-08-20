class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_user, only: [:edit, :update, :destroy]

  def index
    @users = User.all

    if params[:role].present?
      @users = @users.where(role: params[:role])
    end

    if params[:start_date].present? && params[:end_date].present?
      @users = @users.where(created_at: params[:start_date]..params[:end_date])
    end
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to admin_users_path, notice: 'Usuário criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_users_path, notice: 'Usuário atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to admin_users_path, notice: 'Usuário excluído com sucesso.'
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :role, :filial_id, :telephone, :name)
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end

  def partner_status
    user = User.find(params[:id])
    render json: { partner: user.partner }
  end

  def update_partner_status
    user = User.find(params[:id])
    if user.update(partner: params[:partner])
      render json: { success: true, partner: user.partner }
    else
      render json: { success: false, errors: user.errors.full_messages }
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :telephone, :partner, :role, :filial_id)
  end
end
