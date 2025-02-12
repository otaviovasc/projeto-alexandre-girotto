# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  layout "clientside"
  # before_action :configure_sign_up_params, only: [:create]
  # before_action :configure_account_update_params, only: [:update]
  before_action :configure_permitted_parameters, only: [:create, :update]

  # GET /resource/sign_up
  # def new
  #   super
  # end

  # POST /resource
  # def create
  #   super
  # end

  # GET /resource/edit
  # def edit
  #   super
  # end

  # PUT /resource
  # def update
  #   super
  # end

  # DELETE /resource
  # def destroy
  #   super
  # end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  # protected
  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name, :telephone])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name, :telephone])
  end

  # Sobrescreve o método que limpa a sessão após o sign up para preservar os dados necessários.
  def expire_data_after_sign_in!
    # Defina as chaves que você deseja preservar
    keys_to_preserve = ["reserva_params", "cabana_id"]
    # Converte a sessão para hash e, em seguida, utiliza slice para pegar somente as chaves desejadas
    preserved_data = session.to_hash.slice(*keys_to_preserve)

    # Chama o método original que limpa a sessão
    super

    # Restaura os dados preservados na sessão
    preserved_data.each { |key, value| session[key] = value }
  end

  # Redireciona para auto_create se houver dados de reserva na sessão
  def after_sign_up_path_for(resource)
    if session[:reserva_params].present? && session[:cabana_id].present?
      auto_create_reservas_path
    else
      super(resource)
    end
  end

  # Se sua aplicação utiliza contas inativas (ex.: confirmação por e-mail), sobrescreva também este método
  def after_inactive_sign_up_path_for(resource)
    if session[:reserva_params].present? && session[:cabana_id].present?
      auto_create_reservas_path
    else
      super(resource)
    end
  end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_up_params
  #   devise_parameter_sanitizer.permit(:sign_up, keys: [:attribute])
  # end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_account_update_params
  #   devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
  # end

  # The path used after sign up.
  # def after_sign_up_path_for(resource)
  #   super(resource)
  # end

  # The path used after sign up for inactive accounts.
  # def after_inactive_sign_up_path_for(resource)
  #   super(resource)
  # end
end
