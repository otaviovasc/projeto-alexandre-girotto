class Partnership::ReservasController < ApplicationController
  PARTNERSHIP_GOALS = {
    'Serra da Mantiqueira' => { min: 4, max: 8 },
    'Fattoria di Brauna' => { min: 2, max: 4 }
  }.freeze

  helper ReservasHelper

  before_action :authorize_partnership_access
  before_action :set_partnership_reserva, only: [:edit, :update, :confirm_reservation, :cancel]

  def index
    @reference_date = partnership_reference_date
    @summary_year = partnership_summary_year
    @previous_year = @summary_year - 1
    @next_year = @summary_year + 1

    @partnership_reservas = partnership_reserva_scope
                            .includes(:user, :partnership_creator, cabana: :filial)
                            .order(created_at: :desc)

    @monthly_goal_rows = partnership_monthly_goal_rows
    @yearly_summary_rows = partnership_yearly_summary_rows
    @reservas_calendar = Reserva.includes(:cabana).integration_ready
    @top_offset = calendar_top_offsets(@reservas_calendar)
  end

  def new
    setup_form
    @reserva = Reserva.new(observation: 'Parceria')

    render template: 'admin/reservas/new'
  end

  def create
    @user = params[:create_user] == 'true' ? create_or_update_guest : selected_existing_guest
    return unless @user

    @user.update_column(:partner, true) unless @user.partner?

    pending = params[:reservation_state] == 'pending'
    @reserva = Reserva.new(partnership_reserva_params.except(:user_id).merge(
      user: @user,
      payment_status: pending ? 'pending' : 'paid',
      blocks_availability: !pending,
      observation: partnership_reserva_params[:observation].presence || 'Parceria',
      origem: 'sistema',
      partnership_creator: current_user
    ))
    @reserva.total_price = @reserva.calculate_total_price! if @reserva.total_price.blank?

    if @reserva.save
      sync_all_reservas_to_sheets if @reserva.integration_ready?
      notice = pending ? 'Parceria salva como pendente, sem bloquear datas.' : 'Reserva de parceria criada com sucesso.'
      redirect_to partnership_dashboard_path, notice: notice
    else
      render_new_with_error("Não foi possível salvar a reserva. Verifique os dados informados: #{@reserva.errors.full_messages.join(', ')}")
    end
  end

  def edit
    setup_edit_form
    render template: 'admin/reservas/edit'
  end

  def update
    attrs = partnership_reserva_params
    selected_user = User.clients.find_by(id: attrs[:user_id])
    unless selected_user
      setup_edit_form
      flash.now[:alert] = 'Selecione um hóspede válido.'
      render template: 'admin/reservas/edit', status: :unprocessable_entity
      return
    end

    selected_user.update_column(:partner, true) unless selected_user.partner?

    if @reserva.update(attrs.merge(user_id: selected_user.id))
      BreakfastServicesAssigner.new(@reserva).remove_automatic_services
      sync_all_reservas_to_sheets if @reserva.integration_ready?

      redirect_to partnership_dashboard_path(
        start_date: @reserva.start_date.beginning_of_month,
        anchor: 'calendario-parcerias'
      ), notice: 'Parceria atualizada com sucesso.'
    else
      setup_edit_form
      flash.now[:alert] = "Não foi possível alterar a parceria: #{@reserva.errors.full_messages.join(', ')}"
      render template: 'admin/reservas/edit', status: :unprocessable_entity
    end
  end

  def confirm_reservation
    unless @reserva.pending? && !@reserva.blocks_availability?
      redirect_to partnership_dashboard_path, alert: 'Esta parceria não está pendente de confirmação.'
      return
    end

    @reserva.assign_attributes(payment_status: 'paid', blocks_availability: true)

    if @reserva.save
      CleaningServicesAssigner.new(@reserva).call
      sync_all_reservas_to_sheets
      redirect_to partnership_dashboard_path, notice: 'Parceria confirmada e datas bloqueadas.'
    else
      redirect_to partnership_dashboard_path,
                  alert: "Não foi possível reservar estas datas: #{@reserva.errors.full_messages.join(', ')}"
    end
  end

  def cancel
    if @reserva.canceled?
      redirect_to partnership_dashboard_path, alert: 'Esta parceria já está cancelada.'
      return
    end

    @reserva.cancel_for_operations!(by: current_user, reason: params[:cancellation_reason].presence || 'Parceria cancelada pelo painel de parcerias.')
    sync_all_reservas_to_sheets

    redirect_to partnership_dashboard_path, notice: 'Parceria cancelada e datas liberadas.'
  end

  private

  def set_partnership_reserva
    @reserva = partnership_reserva_scope.find(params[:id])
  end

  def authorize_partnership_access
    return if current_user&.partnership_agent? || current_user&.admin?

    redirect_to root_path, alert: 'Você não tem permissão para criar reservas de parceria.'
  end

  def partnership_reserva_scope
    base_scope = Reserva.left_joins(:user)
    base_scope
      .where.not(partnership_creator_id: nil)
      .or(base_scope.where("LOWER(COALESCE(reservas.observation, '')) LIKE ?", '%parceria%'))
      .or(base_scope.where(users: { partner: true }))
      .distinct
  end

  def partnership_reference_date
    date_param = params[:start_date].presence || params[:month].presence
    return Date.strptime(date_param, '%Y-%m') if date_param&.match?(/\A\d{4}-\d{2}\z/)
    return Date.parse(date_param).beginning_of_month if date_param.present?

    Date.current.beginning_of_month
  rescue ArgumentError
    Date.current.beginning_of_month
  end

  def partnership_summary_year
    @reference_date.year
  end

  def partnership_monthly_goal_rows
    month_range = @reference_date.beginning_of_month..@reference_date.end_of_month
    counts_by_filial = partnership_reserva_scope.integration_ready
                       .joins(cabana: :filial)
                       .where(start_date: month_range)
                       .group('filials.name')
                       .count

    PARTNERSHIP_GOALS.map do |filial_name, goal|
      count = counts_by_filial[filial_name].to_i
      status =
        if count < goal[:min]
          :below
        elsif count > goal[:max]
          :above
        else
          :ok
        end

      {
        filial_name: filial_name,
        min: goal[:min],
        max: goal[:max],
        count: count,
        status: status
      }
    end
  end

  def partnership_yearly_summary_rows
    year_range = Date.new(@summary_year, 1, 1)..Date.new(@summary_year, 12, 31)
    counts_by_month_and_filial = Hash.new { |hash, key| hash[key] = Hash.new(0) }

    partnership_reserva_scope.integration_ready
      .includes(cabana: :filial)
      .where(start_date: year_range)
      .each do |reserva|
        counts_by_month_and_filial[reserva.start_date.month][reserva.cabana.filial&.name] += 1
      end

    (1..12).map do |month|
      month_start = Date.new(@summary_year, month, 1)
      {
        month: month,
        month_start: month_start,
        counts: counts_by_month_and_filial[month]
      }
    end
  end

  def calendar_top_offsets(reservas)
    offsets = {}
    reservas.map(&:cabana_id).uniq.each_with_index do |cabana_id, index|
      offsets[cabana_id] = 20 + index * 15
    end
    offsets
  end

  def create_or_update_guest
    user = find_or_initialize_guest
    if user.persisted? && !user.client?
      render_new_with_error('Este e-mail já pertence a um usuário interno do sistema. Use outro e-mail para o hóspede.')
      return
    end

    unless user.save
      render_new_with_error("Não foi possível salvar o hóspede. Verifique os dados informados: #{user.errors.full_messages.join(', ')}")
      return
    end

    user
  end

  def selected_existing_guest
    user = User.clients.find_by(id: partnership_reserva_params[:user_id])
    return user if user

    render_new_with_error('Selecione um hóspede existente ou marque criar novo hóspede.')
    nil
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

  def setup_form
    @partnership_form = true
    @creating_new_guest = false if @creating_new_guest.nil?
    @existing_users = User.clients.order(:name, :email)
    @services = Service.all
  end

  def setup_edit_form
    @partnership_form = true
    @services = Service.order(:name)
  end

  def sync_all_reservas_to_sheets
    return unless GoogleSheetsExportService.configured?

    GoogleSheetsExportService.export_reservas(
      Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
    )
  end

  def render_new_with_error(message)
    setup_form
    @creating_new_guest = params[:create_user] == 'true'
    @reserva ||= Reserva.new(observation: 'Parceria')
    flash.now[:alert] = message
    render template: 'admin/reservas/new', status: :unprocessable_entity
  end

  def partnership_reserva_params
    params.require(:reserva).permit(
      :cabana_id,
      :start_date,
      :end_date,
      :early_checkin,
      :late_checkout,
      :total_price,
      :observation,
      :user_id,
      reserva_services_attributes: [:id, :service_id, :quantity, :service_date, :status, :observation, :_destroy]
    )
  end

  def partnership_user_params
    params.require(:user).permit(:email, :name, :telephone)
  end

end
