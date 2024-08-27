class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    if current_user.admin?
      render :index
    elsif current_user.manager? && current_user.filial.present?
      redirect_to admin_filial_items_path(current_user.filial)
    else
      redirect_to root_path, alert: 'Você não tem acesso de administrador.'
    end
  end
end
