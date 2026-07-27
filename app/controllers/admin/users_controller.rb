class Admin::UsersController < ApplicationController
  OPERATIONS_VIEWER_ACTIONS = %w[index].freeze

  before_action :authenticate_user!
  before_action :authorize_admin_or_operations_viewer
  before_action :block_operations_viewer!, unless: :operations_viewer_allowed_action?
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
      remove_automatic_breakfasts_for_partner(@user) if @user.saved_change_to_partner? && @user.partner?

      redirect_to admin_users_path, notice: 'Usuário atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to admin_users_path, notice: 'Usuário excluído com sucesso.'
  end

  def partner_status
    user = User.find(params[:id])
    render json: { partner: user.partner }
  end

  def update_partner_status
    user = User.find(params[:id])
    if user.update(partner: params[:partner])
      remove_automatic_breakfasts_for_partner(user) if user.saved_change_to_partner? && user.partner?

      render json: { success: true, partner: user.partner }
    else
      render json: { success: false, errors: user.errors.full_messages }
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :telephone, :partner, :role, :filial_id, :password, :password_confirmation)
  end

  def operations_viewer_allowed_action?
    !current_user&.operations_viewer? || OPERATIONS_VIEWER_ACTIONS.include?(action_name)
  end

  def remove_automatic_breakfasts_for_partner(user)
    user.reservas.includes(reserva_services: :service).find_each do |reserva|
      BreakfastServicesAssigner.new(reserva).remove_automatic_services
    end
  end
end
