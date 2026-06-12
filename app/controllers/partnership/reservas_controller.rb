class Partnership::ReservasController < ApplicationController
  before_action :authorize_partnership_access

  def new
    @partnership_form = true
    @reserva = Reserva.new(observation: 'Parceria')
    @services = Service.all

    render template: 'admin/reservas/new'
  end

  def create
    @user = find_or_initialize_guest
    if @user.persisted? && !@user.client?
      render_new_with_error('Este e-mail já pertence a um usuário interno do sistema. Use outro e-mail para o hóspede.')
      return
    end

    unless @user.save
      render_new_with_error("Não foi possível salvar o hóspede. Verifique os dados informados: #{@user.errors.full_messages.join(', ')}")
      return
    end

    @reserva = Reserva.new(partnership_reserva_params.merge(
      user: @user,
      payment_status: 'paid',
      observation: partnership_reserva_params[:observation].presence || 'Parceria',
      origem: 'sistema',
      partnership_creator: current_user
    ))
    @reserva.total_price = @reserva.calculate_total_price! if @reserva.total_price.blank?

    if @reserva.save
      GoogleSheetsExportService.export_reservas(Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)) if GoogleSheetsExportService.configured?
      redirect_to new_partnership_reserva_path, notice: 'Reserva de parceria criada com sucesso.'
    else
      render_new_with_error("Não foi possível salvar a reserva. Verifique os dados informados: #{@reserva.errors.full_messages.join(', ')}")
    end
  end

  private

  def authorize_partnership_access
    return if current_user&.partnership_agent? || current_user&.admin?

    redirect_to root_path, alert: 'Você não tem permissão para criar reservas de parceria.'
  end

  def find_or_initialize_guest
    user = User.find_or_initialize_by(email: partnership_user_params[:email])
    generated_password = SecureRandom.alphanumeric(12)

    user.assign_attributes(partnership_user_params)
    user.partner = true
    user.password = generated_password if user.new_record?
    user.password_confirmation = generated_password if user.new_record?
    user
  end

  def render_new_with_error(message)
    @partnership_form = true
    @reserva ||= Reserva.new(observation: 'Parceria')
    @services = Service.all
    flash.now[:alert] = message
    render template: 'admin/reservas/new', status: :unprocessable_entity
  end

  def partnership_reserva_params
    params.require(:reserva).permit(
      :cabana_id,
      :start_date,
      :end_date,
      :total_price,
      :observation,
      reserva_services_attributes: [:id, :service_id, :quantity, :service_date, :status, :observation, :_destroy]
    )
  end

  def partnership_user_params
    params.require(:user).permit(:email, :name, :telephone)
  end
end
