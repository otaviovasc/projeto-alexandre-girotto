class Admin::ReservasController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_reserva, only: [:edit, :update, :destroy, :show, :update_observation, :update_group_created, :update_service_purchase_access]
  before_action :check_reservations_on_new, only: [:reservas_summary]

  def index
    @reservas = Reserva.includes(:cabana, :user).all

    # Filtros
    @reservas = @reservas.where(cabana_id: params[:cabana_id]) if params[:cabana_id].present?
    @reservas = @reservas.joins(:cabana).where(cabanas: { filial_id: params[:filial_id] }) if params[:filial_id].present?
    if params[:start_date].present? && params[:end_date].present?
      @reservas = @reservas.where(start_date: params[:start_date]..params[:end_date])
    end

    # Ordenação
    case params[:sort]
    when 'start_date_asc'
      @reservas = @reservas.order(start_date: :asc)
    when 'start_date_desc'
      @reservas = @reservas.order(start_date: :desc)
    when 'end_date_asc'
      @reservas = @reservas.order(end_date: :asc)
    when 'end_date_desc'
      @reservas = @reservas.order(end_date: :desc)
    else
      @reservas = @reservas.order(created_at: :desc) # Ordenação padrão
    end
  end

  def new
    @reserva = Reserva.new
    @services = Service.all
  end

  def create
    if params[:create_user] == "true"
      # Criação de um novo usuário
      generated_password = SecureRandom.alphanumeric(8)
      user_attributes = user_params.merge(
        password: generated_password, 
        password_confirmation: generated_password
      )
      
      # Adicionar o campo partner se estiver presente
      user_attributes[:partner] = params[:user][:partner] == 'true' if params[:user] && params[:user][:partner].present?
      
      @user = User.new(user_attributes)

      if @user.save
        @reserva = Reserva.new(reserva_params.merge(user_id: @user.id))
      else
        flash[:alert] = "Não foi possível criar o usuário. Verifique os dados informados: #{@user.errors.full_messages.join(', ')}"
        render :new and return
      end
    elsif params[:reserva][:user_id].present?
      # Seleção de um usuário existente
      @user = User.find_by(id: params[:reserva][:user_id])
      unless @user
        flash[:alert] = "Usuário selecionado não encontrado."
        render :new and return
      end
      @reserva = Reserva.new(reserva_params.merge(user_id: @user.id))
    else
      flash[:alert] = "Você deve selecionar um usuário existente ou criar um novo."
      render :new and return
    end

    # Cálculo do preço total da reserva, se o total_price não estiver presente
    unless params[:reserva][:total_price].present?
      @reserva.total_price = @reserva.calculate_total_price!
    end
    @reserva.payment_status = "paid"

    if @reserva.save
      BreakfastServicesAssigner.new(@reserva, source: 'sistema').add_if_configured

      # Sincroniza automaticamente com Google Sheets ao criar
      GoogleSheetsExportService.export_reservas(Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)) if GoogleSheetsExportService.configured?
      
      # UserMailer.reserva_paid(@user, @reserva).deliver_now
      # UserMailer.notify_adm(@user, @reserva).deliver_now
      redirect_to admin_reservas_summary_path, notice: 'Reserva criada com sucesso e sincronizada com Google Sheets.'
    else
      flash[:alert] = "Não foi possível salvar a reserva. Verifique os dados informados: #{@reserva.errors.full_messages.join(', ')}"
      render :new
    end
  end

  def edit
    @services = Service.all
  end

  def update
    # Atualiza os atributos da reserva
    attrs = reserva_params
    @reserva.manual_override = true if manual_override_update?(attrs)

    if @reserva.update(attrs)
      # Atualiza o status de parceiro do usuário se os parâmetros estiverem presentes
      if params[:reserva][:user_attributes] && params[:reserva][:user_attributes][:partner].present?
        user = @reserva.user
        user.update(partner: params[:reserva][:user_attributes][:partner])
      end
      BreakfastServicesAssigner.new(@reserva).remove_automatic_services if @reserva.user&.partner?

      GoogleSheetsExportService.export_reservas(Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)) if GoogleSheetsExportService.configured?
      
      redirect_to admin_reservas_summary_path, notice: 'Reserva foi atualizada com sucesso.'
    else
      @services = Service.all
      flash.now[:alert] = 'Houve um erro ao atualizar a reserva. Verifique os campos e tente novamente.'
      render :edit
    end
  end

  def destroy
    # Sincroniza exclusão com Google Sheets
    GoogleSheetsExportService.delete_reserva(@reserva.id)
    
    @reserva.destroy
    redirect_to admin_reservas_summary_path, notice: 'Reserva excluída com sucesso.'
  end

  def reservas_summary
    return unless current_user.admin?

    @q = Reserva.ransack(params[:q])
    @reservas = @q.result.includes(:cabana, :user)
                 .order(Arel.sql("CASE WHEN ical_missing_since IS NOT NULL OR ical_date_change_since IS NOT NULL THEN 0 ELSE 1 END ASC"))
                 .order(updated_at: :desc)

    # Estatísticas úteis
    @total_reservas = @reservas.count
    @total_receita  = @reservas.sum(:total_price)
    @reservas_por_status = @reservas.unscope(:order).group(:payment_status).count
    @reservas_por_cabana = @reservas.unscope(:order).joins(:cabana).group('cabanas.name').count

    @reservas_calendar = Reserva.includes(:cabana).where(payment_status: 'paid')

    cabana_ids = @reservas_calendar.map(&:cabana_id).uniq
    @top_offset = {}
    cabana_ids.each_with_index do |cabana_id, index|
      @top_offset[cabana_id] = 20 + index * 15
    end

    # Busca todas as cabanas para montar a lista de links
    @cabanas = Cabana.all

    # Monta a lista de import_links com OpenStruct para facilitar a view
    @import_links = []
    plataformas_set = Set.new

    @cabanas.each do |cabana|
      next if cabana.import_links.blank?

      begin
        links_hash = JSON.parse(cabana.import_links)
      rescue JSON::ParserError
        links_hash = {}
      end

      links_hash.each do |platform, url|
        plataformas_set.add(platform)
        @import_links << OpenStruct.new(
          cabana: cabana,
          platform: platform,
          url: url
        )
      end
    end

    @plataformas = plataformas_set.to_a.sort
  end

  def export_csv
    @reservas = Reserva.includes(:cabana, :user, reserva_services: :service)
    
    # Filtros opcionais
    @reservas = @reservas.where(cabana_id: params[:cabana_id]) if params[:cabana_id].present?
    @reservas = @reservas.joins(:cabana).where(cabanas: { filial_id: params[:filial_id] }) if params[:filial_id].present?
    if params[:start_date].present? && params[:end_date].present?
      @reservas = @reservas.where(start_date: params[:start_date]..params[:end_date])
    end
    
    @reservas = @reservas.order(created_at: :desc)
    
    csv_data = ReservasExportService.to_csv(@reservas)
    
    # Adiciona BOM para UTF-8 (Excel compatibilidade)
    bom = "\xEF\xBB\xBF"
    csv_with_bom = bom + csv_data
    
    filename = "reservas_export_#{Date.today.strftime('%Y%m%d')}.csv"
    
    send_data csv_with_bom,
              filename: filename,
              type: 'text/csv; charset=utf-8',
              disposition: 'attachment'
  end

  def export_sheets
    @reservas = Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)

    # Aplica os mesmos filtros do Ransack se estiverem presentes
    if params[:q].present?
      @q = Reserva.ransack(params[:q])
      @reservas = @q.result.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
    end
    
    # Filtros manuais (se houver, compatibilidade com export_csv)
    @reservas = @reservas.where(cabana_id: params[:cabana_id]) if params[:cabana_id].present?
    @reservas = @reservas.joins(:cabana).where(cabanas: { filial_id: params[:filial_id] }) if params[:filial_id].present?
    if params[:start_date].present? && params[:end_date].present?
      @reservas = @reservas.where(start_date: params[:start_date]..params[:end_date])
    end
    
    result = GoogleSheetsExportService.export_reservas(@reservas)
    
    redirect_path = if params[:id].present? && params[:redirect_to] == 'edit'
                      edit_admin_reserva_path(params[:id])
                    elsif params[:id].present? && params[:redirect_to] == 'show'
                      admin_reserva_path(params[:id])
                    else
                      admin_reservas_summary_path(q: params[:q]&.permit!) # Mantém os filtros no redirect
                    end
    
    if result[:success]
      redirect_to redirect_path, notice: "✅ #{result[:message]}"
    else
      redirect_to redirect_path, alert: "❌ Erro ao exportar: #{result[:error]}"
    end
  end



  def plataformas_disponiveis
    plataformas = Set.new

    Cabana.all.each do |cabana|
      next if cabana.import_links.blank?
      begin
        links_hash = JSON.parse(cabana.import_links)
        links_hash.keys.each { |platform| plataformas.add(platform) }
      rescue JSON::ParserError
      end
    end

    @plataformas = plataformas.to_a.sort
  end

  def plataformas_import
    plataformas = Set.new

    Cabana.all.each do |cabana|
      next if cabana.import_links.blank?
      begin
        links_hash = JSON.parse(cabana.import_links)
        links_hash.keys.each { |platform| plataformas.add(platform) }
      rescue JSON::ParserError
        # ignora
      end
    end

    @plataformas = plataformas.to_a.sort
  end

  def update_observation
    if @reserva.update_column(:observation, params[:observation])
      GoogleSheetsExportService.export_reservas(Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)) if GoogleSheetsExportService.configured?
      flash[:notice] = "Observação atualizada com sucesso"
    else
      flash[:alert] = "Erro ao atualizar observação"
    end
    redirect_to admin_reservas_summary_path
  end

  def update_group_created
    group_created = ActiveModel::Type::Boolean.new.cast(params[:group_created])
    if group_created
      @reserva.update_columns(group_created: true, ical_date_change_since: nil)
    else
      @reserva.update_column(:group_created, false)
    end

    sheets_result = if GoogleSheetsExportService.configured?
                      GoogleSheetsExportService.export_reservas(
                        Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
                      )
                    else
                      { success: true }
    end

    if sheets_result[:success]
      render json: {
        success: true,
        group_created: @reserva.group_created?,
        ical_date_changed: @reserva.ical_date_changed?
      }
    else
      render json: {
        success: true,
        group_created: @reserva.group_created?,
        ical_date_changed: @reserva.ical_date_changed?,
        sheets_synced: false,
        error: sheets_result[:error]
      }, status: :accepted
    end
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def update_service_purchase_access
    enabled = ActiveModel::Type::Boolean.new.cast(params[:service_purchase_override])

    if enabled && (@reserva.start_date.blank? || Date.current > @reserva.start_date)
      redirect_to admin_reserva_path(@reserva), alert: 'O check-in desta reserva já passou; não é possível liberar novas compras.'
      return
    end

    @reserva.update_columns(service_purchase_override: enabled, updated_at: Time.current)

    message = if enabled
                "Compra de serviços liberada para esta reserva até o check-in em #{@reserva.start_date.strftime('%d/%m/%Y')}."
              else
                'Liberação especial de compra de serviços revogada.'
              end

    redirect_to admin_reserva_path(@reserva), notice: message
  end

  def import_platform_calendar
    unless params[:cabana_id].present? && params[:platform].present?
      redirect_to select_cabana_import_admin_reservas_path, alert: "Selecione a cabana e a plataforma."
      return
    end

    begin
      cabana = Cabana.find(params[:cabana_id])
      platform_param = params[:platform].to_s
      platform = platform_param.downcase

      import_links = {}
      if cabana.import_links.present?
        begin
          import_links = JSON.parse(cabana.import_links)
        rescue JSON::ParserError
          import_links = {}
        end
      end
      platform_link = import_links[platform_param] ||
                      import_links[platform] ||
                      import_links.find { |key, _url| key.to_s.casecmp(platform_param).zero? }&.last

      unless platform_link.present?
        redirect_to admin_reservas_summary_path, alert: "Link para #{platform.capitalize} não configurado para esta cabana."
        return
      end

      result = IcalReservationImporter.new(cabana: cabana, platform: platform, url: platform_link).call

      redirect_to admin_reservas_summary_path,
                  notice: "#{result.created} reservas criadas, #{result.updated} atualizadas, #{result.missing} possíveis cancelamentos e #{result.skipped} já estavam em dia para #{cabana.name}."
    rescue => e
      redirect_to admin_reservas_summary_path, alert: "Erro ao importar reservas do #{params[:platform]}: #{e.message}"
    end
  end

  def select_cabana_import
    @cabana = Cabana.find_by(id: params[:cabana_id])
    if @cabana.nil?
      redirect_to admin_reservas_summary_path, alert: "Cabana não encontrada"
      return
    end

    begin
      links_hash = JSON.parse(@cabana.import_links || "{}")
      @platform_links = links_hash
    rescue JSON::ParserError
      @platform_links = {}
    end
  end

  def check_reservations_on_new
    @reservas = Reserva.where('end_date > ?', Date.today)
    @reservas.each do |reserva|
      if reserva.expired? && (reserva.waiting_payment? || reserva.pending?)
        reserva.update_column(:payment_status, 'canceled')
      end
    end
  end

  private

  def set_reserva
    @reserva = Reserva.find(params[:id])
  end

 
  def reserva_params
    params.require(:reserva).permit(
      :cabana_id, 
      :user_id, 
      :start_date, 
      :end_date, 
      :total_price, 
      :observation,
      :group_created,
      user_attributes: [:id, :partner],
      reserva_services_attributes: [:id, :service_id, :quantity, :service_date, :status, :observation, :_destroy]
    )
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :name, :telephone, :partner)
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end

  def manual_override_update?(attrs)
    return false unless @reserva.imported?

    attrs_hash = attrs.to_h

    %w[start_date end_date cabana_id].any? do |attribute|
      next false unless attrs_hash.key?(attribute)

      incoming = attrs_hash[attribute]
      next false if incoming.blank?

      current = @reserva.public_send(attribute)
      normalized =
        if attribute == 'cabana_id'
          incoming.to_i
        else
          Date.parse(incoming.to_s)
        end

      normalized != current
    end
  end
end
