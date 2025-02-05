class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  def after_sign_in_path_for(resource)
    restore_reserva_path || session.delete(:return_to) || root_path
  end

  def after_sign_up_path_for(resource)
    restore_reserva_path || session.delete(:return_to) || root_path
  end

  private

  def restore_reserva_path
    if session[:reserva_params].present?
      cabana_id = session[:cabana_id]
      new_cabana_reserva_path(cabana_id: cabana_id)
    end
  end
end
