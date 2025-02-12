class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :store_user_location!, if: :should_store_location?

  private

  def store_user_location!
    store_location_for(:user, request.fullpath)
  end

  def should_store_location?
    request.get? &&
      !request.xhr? && # Evita chamadas AJAX
      !request.path.match?(/\/calculate_price|\/unavailable_dates/) && # Evita salvar URLs de AJAX
      !devise_controller? &&
      !request.path.in?([new_user_registration_path, new_user_session_path])
  end

  def after_sign_in_path_for(resource)
    if session[:reserva_params].present? && session[:cabana_id].present?
      auto_create_reservas_path
    else
      stored_location_for(resource) || root_path
    end
  end
end
