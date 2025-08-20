class Admin::ReservasController < ApplicationController
  require 'open-uri'

  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_reserva, only: [:edit, :update, :destroy, :show, :update_observation]
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
      # UserMailer.reserva_paid(@user, @reserva).deliver_now
      # UserMailer.notify_adm(@user, @reserva).deliver_now
      redirect_to admin_reservas_summary_path, notice: 'Reserva criada com sucesso.'
    else
      flash[:alert] = "Não foi possível salvar a reserva. Verifique os dados informados: #{@reserva.errors.full_messages.join(', ')}"
      render :new
    end
  end

  def edit
  end

  def update
    # Atualiza os atributos da reserva
    if @reserva.update(reserva_params)
      # Atualiza o status de parceiro do usuário se os parâmetros estiverem presentes
      if params[:reserva][:user_attributes] && params[:reserva][:user_attributes][:partner].present?
        user = @reserva.user
        user.update(partner: params[:reserva][:user_attributes][:partner])
      end
      
      redirect_to admin_reservas_summary_path, notice: 'Reserva foi atualizada com sucesso.'
    else
      flash.now[:alert] = 'Houve um erro ao atualizar a reserva. Verifique os campos e tente novamente.'
      render :edit
    end
  end

  def destroy
    @reserva.destroy
    redirect_to admin_reservas_summary_path, notice: 'Reserva was successfully deleted.'
  end

  def reservas_summary
    return unless current_user.admin?

    @q = Reserva.ransack(params[:q])
    @reservas = @q.result.includes(:cabana, :user).order(updated_at: :desc)

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
      flash[:notice] = "Observação atualizada com sucesso"
    else
      flash[:alert] = "Erro ao atualizar observação"
    end
    redirect_to admin_reservas_summary_path
  end

  def import_platform_calendar
    unless params[:cabana_id].present? && params[:platform].present?
      redirect_to select_cabana_import_admin_reservas_path, alert: "Selecione a cabana e a plataforma."
      return
    end

    begin
      cabana = Cabana.find(params[:cabana_id])
      platform = params[:platform].downcase

      import_links = {}
      if cabana.import_links.present?
        begin
          import_links = JSON.parse(cabana.import_links)
        rescue JSON::ParserError
          import_links = {}
        end
      end
      platform_link = import_links[platform]

      unless platform_link.present?
        redirect_to admin_reservas_summary_path, alert: "Link para #{platform.capitalize} não configurado para esta cabana."
        return
      end

      ics_content = URI.parse(platform_link).open.read
      calendars = Icalendar::Calendar.parse(ics_content)
      calendar = calendars.first

      count = 0

      calendar.events.each do |event|
        start_date = event.dtstart.to_date
        end_date   = event.dtend.to_date - 1.day

        next if start_date < Date.current
        next if start_date > Date.current + 11.months
        end_date = start_date + 1.day if end_date <= start_date

        # Conjunto de todos os dias do evento
        dias_livres = (start_date..end_date).to_a

        # Remove dias já ocupados
        reservas_existentes = Reserva.where(cabana_id: cabana.id)
          .where("start_date <= ? AND end_date >= ?", end_date, start_date)
          .where(payment_status: %w[pending waiting_payment paid])

        reservas_existentes.each do |reserva|
          dias_ocupados = (reserva.start_date..reserva.end_date).to_a
          dias_livres -= dias_ocupados
        end

        # Se não sobrou nenhum dia livre, pula
        next if dias_livres.empty?

        # Agrupa dias contínuos
        blocos = dias_livres.chunk_while { |d1, d2| d2 == d1 + 1 }.to_a

        # Garante que o usuário da plataforma exista
        user = User.find_or_create_by!(email: "#{platform}@importado.com") do |u|
          u.name = platform.capitalize
          u.telephone = "000000001"
          u.password = "password"
          u.password_confirmation = "password"
        end

        # Cria reservas para cada bloco livre
        blocos.each do |bloco|
          Reserva.create!(
            start_date: bloco.first,
            end_date: bloco.last,
            user: user,
            cabana: cabana,
            origem: platform,
            payment_status: 'paid',
            total_price: 0.0,
            observation: "Importado via #{platform.capitalize} - #{cabana.name}"
          )
          count += 1
        end
      end

      redirect_to admin_reservas_summary_path, notice: "#{count} reservas importadas do #{platform.capitalize} para #{cabana.name}!"
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
      user_attributes: [:id, :partner]
    )
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :name, :telephone, :partner)
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end