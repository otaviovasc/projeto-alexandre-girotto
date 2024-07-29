class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    if current_user.admin?
      redirect_to admin_users_path
    elsif current_user.manager? && current_user.filial.present?
      redirect_to filial_items_path(current_user.filial)
    else
      redirect_to root_path, alert: 'You do not have access to any filials.'
    end
  end
end
