class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :store_user_location!, if: :should_store_location?
  before_action :restrict_partnership_agent_access

  helper_method :operations_viewer_access?, :hide_financials?, :can_manage_reservations?

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
    sync_user_filial_after_sign_in(resource)

    return partnership_dashboard_path if resource.respond_to?(:partnership_agent?) && resource.partnership_agent?

    if session[:reserva_params].present? && session[:cabana_id].present?
      auto_create_reservas_path
    else
      stored_location_for(resource) || root_path
    end
  end

  def sync_user_filial_after_sign_in(resource)
    return unless resource.respond_to?(:sync_filial_from_cabana!)

    if session[:cabana_id].present?
      cabana = Cabana.find_by(id: session[:cabana_id])
      resource.sync_filial_from_cabana!(cabana)
    elsif resource.respond_to?(:sync_filial_from_latest_reserva!)
      resource.sync_filial_from_latest_reserva!
    end
  end

  def restrict_partnership_agent_access
    return unless current_user&.partnership_agent?
    return if devise_controller?
    return if partnership_agent_allowed_path?

    redirect_to new_partnership_reserva_path, alert: 'Seu acesso está limitado à criação de reservas de parceria.'
  end

  def partnership_agent_allowed_path?
    request.path.start_with?('/parcerias') ||
      request.path.match?(%r{\A/cabanas/\d+/unavailable_dates\z})
  end

  def operations_viewer_access?
    current_user&.operations_viewer?
  end

  def hide_financials?
    current_user&.financial_data_hidden?
  end

  def can_manage_reservations?
    current_user&.can_manage_reservations?
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user&.admin?
  end

  def authorize_admin_or_operations_viewer
    return if current_user&.admin_or_operations_viewer?

    redirect_to root_path, alert: 'Você não tem permissão para acessar esta área.'
  end

  def block_operations_viewer!
    return unless current_user&.operations_viewer?

    redirect_to admin_reservas_summary_path, alert: 'Acesso somente para visualização.'
  end
end
