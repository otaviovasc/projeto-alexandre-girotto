class Admin::ReservasController < ApplicationController
  RESERVAS_SUMMARY_RECENT_LIMIT = 20
  OPERATIONS_VIEWER_ACTIONS = %w[index show reservas_summary canceladas nao_finalizadas fnrh_bypass_precheckin].freeze

  before_action :authenticate_user!
  before_action :authorize_admin_or_operations_viewer
  before_action :block_operations_viewer!, unless: :operations_viewer_allowed_action?
  before_action :set_reserva, only: [
    :edit, :update, :destroy, :cancel, :show, :update_observation, :update_group_created,
    :acknowledge_ical_date_change, :update_service_purchase_access, :update_service_purchase_late_fee,
    :update_service_installments, :sync_fnrh,
    :fnrh_check_in, :fnrh_no_show, :fnrh_checkout, :fnrh_cancel, :fnrh_bypass_precheckin,
    :confirm_reservation, :sync_service_payment
  ]
  before_action :check_reservations_on_new, only: [:reservas_summary], if: -> { current_user&.admin? }

  def index
    @reservas = Reserva.active_for_operations.includes(:cabana, :user).all

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

  def show
    @pending_service_payments = pending_service_payment_items.to_a
  end

  def new
    @reserva = Reserva.new(observation: 'Sistema')
    load_new_form_collections
  end

  def create
    @creating_new_guest = params[:create_user] == "true"
    @reserva = Reserva.new(reserva_params.except(:user_id))

    if @creating_new_guest
      generated_password = SecureRandom.alphanumeric(8)
      user_attributes = user_params.merge(
        password: generated_password,
        password_confirmation: generated_password
      )
      user_attributes[:partner] = params.dig(:user, :partner) == 'true'
      @user = User.new(user_attributes)
      @reserva.user = @user

      unless @user.valid?
        load_new_form_collections
        flash.now[:alert] = "Não foi possível criar o usuário. Corrija os dados sem perder a reserva: #{@user.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
        return
      end
    elsif params[:reserva][:user_id].present?
      @user = User.find_by(id: params[:reserva][:user_id])
      unless @user
        load_new_form_collections
        flash.now[:alert] = "Usuário selecionado não encontrado."
        render :new, status: :unprocessable_entity
        return
      end
    else
      load_new_form_collections
      flash.now[:alert] = "Você deve selecionar um usuário existente ou criar um novo."
      render :new, status: :unprocessable_entity
      return
    end

    @reserva.user = @user
    @reserva.observation = @user.partner? ? 'Parceria' : @reserva.observation.presence || 'Sistema'

    pending_reservation = params[:reservation_state] == 'pending'
    pending_hold_hours = pending_payment_hold_hours

    if pending_reservation
      @reserva.payment_status = 'waiting_payment'
      @reserva.blocks_availability = true
      @reserva.payment_expires_at = pending_hold_hours.hours.from_now
    else
      @reserva.payment_status = 'paid'
      @reserva.blocks_availability = true
      @reserva.payment_expires_at = nil
    end

    unless params[:reserva][:total_price].present?
      @reserva.total_price = @reserva.calculate_total_price!
    end

    if (blocked_service_error = service_holiday_block_error(@reserva))
      load_new_form_collections
      flash.now[:alert] = blocked_service_error
      render :new, status: :unprocessable_entity
      return
    end

    begin
      Reserva.transaction do
        @user.save! if @user.new_record?
        @reserva.save!
      end

      if pending_reservation
        begin
          ReservaPendingPaymentSetup.call(
            reserva: @reserva,
            payments_attributes: params[:pending_payments] || {},
            hold_hours: pending_hold_hours,
            max_credit_card_installments: params[:pending_payment_max_credit_card_installments]
          )
        rescue => payment_error
          @reserva.cancel_for_operations!(by: current_user, reason: "Erro ao gerar pagamento pendente: #{payment_error.message}")
          load_new_form_collections
          flash.now[:alert] = "A reserva foi salva, mas não foi possível gerar os links de pagamento: #{payment_error.message}"
          render :new, status: :unprocessable_entity
          return
        end
      elsif @reserva.integration_ready?
        BreakfastServicesAssigner.new(@reserva, source: 'sistema').add_if_configured
      end

      sync_all_reservas_to_sheets if @reserva.integration_ready?

      if pending_reservation
        redirect_to admin_reserva_path(@reserva), notice: 'Reserva pendente criada. As datas estão pré-travadas até o prazo do primeiro pagamento.'
        return
      end

      message = if @reserva.blocks_availability?
                  'Reserva criada e datas bloqueadas com sucesso.'
                else
                  'Reserva salva como pendente, sem bloquear as datas.'
                end
      redirect_to admin_reservas_summary_path, notice: message
    rescue ActiveRecord::RecordInvalid => error
      load_new_form_collections
      record_errors = error.record.errors.full_messages
      flash.now[:alert] = "Não foi possível salvar. Corrija os dados sem perder a reserva: #{record_errors.join(', ')}"
      render :new, status: :unprocessable_entity
    end
  end

  def confirm_reservation
    unless @reserva.pending? && !@reserva.blocks_availability?
      redirect_to admin_reserva_path(@reserva), alert: 'Esta reserva não está pendente de confirmação.'
      return
    end

    @reserva.assign_attributes(payment_status: 'paid', blocks_availability: true)

    if @reserva.save
      CleaningServicesAssigner.new(@reserva).call
      BreakfastServicesAssigner.new(@reserva, source: 'sistema').add_if_configured
      sync_all_reservas_to_sheets
      redirect_to admin_reserva_path(@reserva), notice: 'Reserva confirmada. As datas agora estão bloqueadas.'
    else
      redirect_to admin_reserva_path(@reserva), alert: "Não foi possível reservar estas datas: #{@reserva.errors.full_messages.join(', ')}"
    end
  end

  def edit
    @services = Service.all
  end

  def update
    # Atualiza os atributos da reserva
    attrs = reserva_params
    @reserva.manual_override = true if manual_override_update?(attrs)
    @reserva.assign_attributes(attrs)

    if (blocked_service_error = service_holiday_block_error(@reserva))
      @services = Service.all
      flash.now[:alert] = blocked_service_error
      render :edit, status: :unprocessable_entity
      return
    end

    if @reserva.save
      # Atualiza o status de parceiro do usuário se os parâmetros estiverem presentes
      if params[:reserva][:user_attributes] && params[:reserva][:user_attributes][:partner].present?
        user = @reserva.user
        user.update(partner: params[:reserva][:user_attributes][:partner])
      end
      BreakfastServicesAssigner.new(@reserva).remove_automatic_services if @reserva.user&.partner?

      sync_all_reservas_to_sheets if @reserva.integration_ready?
      
      redirect_to admin_reservas_summary_path, notice: 'Reserva foi atualizada com sucesso.'
    else
      @services = Service.all
      flash.now[:alert] = 'Houve um erro ao atualizar a reserva. Verifique os campos e tente novamente.'
      render :edit
    end
  end

  def destroy
    cancel
  end

  def cancel
    fnrh_error = nil

    begin
      Fnrh::TransitionService.new(@reserva, source: 'manual').cancel if @reserva.fnrh_reservation_id.present?
    rescue => e
      fnrh_error = e.message
    end

    @reserva.cancel_for_operations!(by: current_user, reason: params[:cancellation_reason])
    sync_all_reservas_to_sheets

    if fnrh_error.present?
      redirect_to admin_reservas_summary_path,
                  alert: "Reserva cancelada no sistema, mas a FNRH retornou erro: #{fnrh_error}"
    else
      redirect_to admin_reservas_summary_path, notice: 'Reserva cancelada e movida para o histórico.'
    end
  end

  def sync_service_payment
    order_code = params[:order_code].to_s.strip
    cart_item = CartItem.includes(reserva: { cabana: :filial })
                        .where(reserva_id: @reserva.id, payment_status: 'waiting_payment')
                        .find_by(payment_order_code: order_code)

    unless cart_item
      redirect_to admin_reserva_path(@reserva), alert: 'Pedido de serviço pendente não encontrado nesta reserva.'
      return
    end

    result = CieloPendingPaymentSync.sync_order_code(
      order_code: cart_item.payment_order_code,
      filial: cart_item.reserva.cabana.filial
    )

    redirect_to admin_reserva_path(@reserva), service_payment_sync_flash_for(result)
  rescue => e
    redirect_to admin_reserva_path(@reserva), alert: "Não foi possível conferir na Cielo: #{e.message}"
  end

  def reservas_summary
    @q = Reserva.active_for_operations.ransack(summary_ransack_params)
    filtered_reservas = apply_general_search(@q.result)

    # Estatísticas úteis
    @total_reservas = filtered_reservas.count
    @total_receita  = filtered_reservas.sum(:total_price)
    @reservas_por_status = filtered_reservas.unscope(:order).group(:payment_status).count
    @reservas_por_cabana = filtered_reservas.unscope(:order).joins(:cabana).group('cabanas.name').count

    @summary_list_limited = summary_list_limited?
    @reservas = summary_list_scope(filtered_reservas)
                .includes(:cabana, :user, :reserva_payments)
                .order(summary_priority_order)
                .order(updated_at: :desc)
    @displayed_reservas_count = @reservas.size

    @calendar_start_date = summary_calendar_start_date
    calendar_start = @calendar_start_date.beginning_of_month.beginning_of_week
    calendar_end = @calendar_start_date.end_of_month.end_of_week

    @reservas_calendar = Reserva.includes(:cabana)
                                 .integration_ready
                                 .where('start_date <= ? AND end_date >= ?', calendar_end + 1.day, calendar_start - 1.day)
                                 .order(:start_date)

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

  def canceladas
    load_history_reservas(
      Reserva.canceled_for_external_history,
      title: 'Reservas Canceladas',
      description: 'Histórico preservado das reservas reais que saíram da operação ativa.',
      count_label: 'Canceladas',
      table_title: 'Histórico de cancelamentos',
      date_label: 'Cancelada em',
      empty_message: 'Nenhuma reserva cancelada encontrada.',
      search_path: canceladas_admin_reservas_path
    )
  end

  def nao_finalizadas
    load_history_reservas(
      Reserva.unfinished_pre_reservations,
      title: 'Pré-reservas não finalizadas',
      description: 'Pré-reservas que tiveram link de pagamento criado, mas nunca tiveram pagamento confirmado.',
      count_label: 'Não finalizadas',
      table_title: 'Histórico de pré-reservas não finalizadas',
      date_label: 'Não finalizada em',
      empty_message: 'Nenhuma pré-reserva não finalizada encontrada.',
      search_path: nao_finalizadas_admin_reservas_path
    )

    render :canceladas
  end

  def export_csv
    @reservas = Reserva.active_for_operations.ransack(summary_ransack_params)
                        .result
                        .includes(:cabana, :user, reserva_services: :service)
    @reservas = apply_general_search(@reservas)
    
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
    @reservas = Reserva.active_for_operations.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)

    # Aplica os mesmos filtros do Ransack se estiverem presentes
    if params[:q].present?
      @q = Reserva.active_for_operations.ransack(summary_ransack_params)
      @reservas = @q.result.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
    end
    @reservas = apply_general_search(@reservas)
    
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
                      admin_reservas_summary_path(q: summary_ransack_params, search: params[:search])
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
    @reserva.update_column(:group_created, group_created)
    sync_group_created_side_effects_async(@reserva.id, group_created)

    render json: {
      success: true,
      group_created: @reserva.group_created?,
      ical_date_changed: @reserva.ical_date_changed?
    }
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def sync_fnrh
    if Fnrh::ReservationSyncService.new(@reserva, source: 'manual').call(force: true)
      redirect_to admin_reserva_path(@reserva), notice: 'Reserva sincronizada com a FNRH.'
    else
      redirect_to admin_reserva_path(@reserva), alert: @reserva.reload.fnrh_last_error.presence || 'A reserva ainda não atende aos critérios da FNRH.'
    end
  end

  def fnrh_check_in
    Fnrh::TransitionService.new(@reserva, source: 'manual').check_in
    redirect_to admin_reserva_path(@reserva), notice: 'Check-in registrado na FNRH.'
  rescue => e
    redirect_to admin_reserva_path(@reserva), alert: e.message
  end

  def fnrh_no_show
    Fnrh::TransitionService.new(@reserva, source: 'manual').no_show
    redirect_to admin_reserva_path(@reserva), notice: 'No-show registrado na FNRH.'
  rescue => e
    redirect_to admin_reserva_path(@reserva), alert: e.message
  end

  def fnrh_checkout
    Fnrh::TransitionService.new(@reserva, source: 'manual').check_out
    redirect_to admin_reserva_path(@reserva), notice: 'Checkout registrado na FNRH.'
  rescue => e
    redirect_to admin_reserva_path(@reserva), alert: e.message
  end

  def fnrh_cancel
    Fnrh::TransitionService.new(@reserva, source: 'manual').cancel
    redirect_to admin_reserva_path(@reserva), notice: 'Cancelamento registrado na FNRH.'
  rescue => e
    redirect_to admin_reserva_path(@reserva), alert: e.message
  end

  def fnrh_bypass_precheckin
    Fnrh::TransitionService.new(@reserva, source: 'manual').bypass_precheckin
    redirect_to admin_reserva_path(@reserva), notice: 'FNRH pulada manualmente. O material do hóspede foi liberado.'
  rescue => e
    redirect_to admin_reserva_path(@reserva), alert: e.message
  end

  def acknowledge_ical_date_change
    acknowledged_at = Time.current

    Reserva.transaction do
      @reserva.update_column(:ical_date_change_since, nil)
      @reserva.ical_reservation_changes
              .where(acknowledged_at: nil)
              .update_all(acknowledged_at: acknowledged_at, updated_at: acknowledged_at)
    end

    redirect_to admin_reservas_summary_path,
                notice: "Troca de datas da reserva ##{@reserva.id} marcada como concluída."
  end

  def update_service_purchase_access
    enabled = ActiveModel::Type::Boolean.new.cast(params[:service_purchase_override])

    if enabled
      deadline = service_purchase_override_deadline_param || @reserva.end_date || @reserva.start_date

      if deadline.blank?
        redirect_to admin_reserva_path(@reserva), alert: 'Informe uma data final para liberar a compra de serviços.'
        return
      end

      if Date.current > deadline
        redirect_to admin_reserva_path(@reserva), alert: 'A data final da liberação já passou.'
        return
      end

      if @reserva.end_date.present? && deadline > @reserva.end_date
        redirect_to admin_reserva_path(@reserva), alert: 'A liberação de compra não pode passar do check-out.'
        return
      end

      @reserva.update_columns(
        service_purchase_override: true,
        service_purchase_override_until: deadline,
        updated_at: Time.current
      )
    else
      @reserva.update_columns(
        service_purchase_override: false,
        service_purchase_override_until: nil,
        updated_at: Time.current
      )
    end

    message = if enabled
                "Compra de serviços liberada para esta reserva até #{deadline.strftime('%d/%m/%Y')}."
              else
                'Liberação especial de compra de serviços revogada.'
              end

    redirect_to admin_reserva_path(@reserva), notice: message
  end

  def update_service_purchase_late_fee
    waived = ActiveModel::Type::Boolean.new.cast(params[:service_purchase_late_fee_waived])
    @reserva.update_columns(service_purchase_late_fee_waived: waived, updated_at: Time.current)

    message = if waived
                'Taxa administrativa para compra fora do prazo anulada para esta reserva.'
              else
                'Taxa administrativa para compra fora do prazo reativada para esta reserva.'
              end

    redirect_to admin_reserva_path(@reserva), notice: message
  end

  def update_service_installments
    max_installments = params[:service_max_installments].to_i

    unless max_installments.between?(1, 12)
      redirect_to admin_reserva_path(@reserva), alert: 'Selecione entre 1x e 12x para os serviços.'
      return
    end

    @reserva.update_columns(service_max_installments: max_installments, updated_at: Time.current)
    redirect_to admin_reserva_path(@reserva), notice: "Parcelamento dos serviços definido em até #{max_installments}x."
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
    ReservaPaymentExpiry.run
  end

  private

  def load_history_reservas(scope, title:, description:, count_label:, table_title:, date_label:, empty_message:, search_path:)
    @history_title = title
    @history_description = description
    @history_count_label = count_label
    @history_table_title = table_title
    @history_date_label = date_label
    @history_empty_message = empty_message
    @history_search_path = search_path

    @q = scope.ransack(summary_ransack_params)
    filtered_reservas = apply_general_search(@q.result)
    @reservas = filtered_reservas.includes(:cabana, :user, :canceled_by, reserva_services: :service)
                                 .order(canceled_at: :desc, updated_at: :desc)

    @total_reservas = @reservas.count
    @total_receita = @reservas.sum(:total_price)
  end

  def sync_group_created_side_effects_async(reserva_id, group_created)
    Thread.new do
      Rails.application.executor.wrap do
        reserva = Reserva.find_by(id: reserva_id)
        next unless reserva

        Fnrh::ReservationSyncService.new(reserva, source: 'admin').call if group_created

        if GoogleSheetsExportService.configured?
          GoogleSheetsExportService.export_reservas(
            Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
          )
        end
      rescue => e
        Rails.logger.error "Erro ao sincronizar grupo criado em segundo plano: #{e.message}"
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end
  end

  def summary_priority_order
    Arel.sql(
      "CASE " \
      "WHEN payment_status IN ('pending', 'waiting_payment') THEN 0 " \
      "WHEN EXISTS (SELECT 1 FROM reserva_payments WHERE reserva_payments.reserva_id = reservas.id AND reserva_payments.payment_status = 'late_paid') THEN 1 " \
      "WHEN EXISTS (SELECT 1 FROM reserva_payments WHERE reserva_payments.reserva_id = reservas.id AND reserva_payments.payment_status = 'overdue') THEN 2 " \
      "WHEN group_created = FALSE THEN 3 " \
      "WHEN ical_date_change_since IS NOT NULL THEN 4 " \
      "WHEN ical_missing_since IS NOT NULL THEN 5 " \
      "ELSE 6 END ASC"
    )
  end

  def summary_list_limited?
    params[:search].blank? && summary_ransack_params.to_h.values.all?(&:blank?)
  end

  def summary_list_scope(scope)
    return scope unless summary_list_limited?

    priority_scope = scope.where(
      "payment_status IN ('pending', 'waiting_payment') OR " \
      "EXISTS (SELECT 1 FROM reserva_payments WHERE reserva_payments.reserva_id = reservas.id AND reserva_payments.payment_status = 'late_paid') OR " \
      "EXISTS (SELECT 1 FROM reserva_payments WHERE reserva_payments.reserva_id = reservas.id AND reserva_payments.payment_status = 'overdue') OR " \
      "group_created = FALSE OR ical_date_change_since IS NOT NULL OR ical_missing_since IS NOT NULL"
    )
    priority_ids = priority_scope.pluck(:id)
    recent_ids = scope.where.not(id: priority_ids)
                      .order(updated_at: :desc)
                      .limit(RESERVAS_SUMMARY_RECENT_LIMIT)
                      .pluck(:id)

    scope.where(id: priority_ids + recent_ids)
  end

  def summary_calendar_start_date
    Date.parse(params[:start_date].to_s)
  rescue ArgumentError, TypeError
    Date.current
  end

  def load_new_form_collections
    @services = Service.order(:name)
  end

  def pending_payment_hold_hours
    value = params[:pending_payment_hold_hours].to_s.tr(',', '.')
    hours = BigDecimal(value)
    hours.positive? ? hours : ReservaPendingPaymentSetup::DEFAULT_HOLD_HOURS
  rescue ArgumentError, TypeError
    ReservaPendingPaymentSetup::DEFAULT_HOLD_HOURS
  end

  def service_holiday_block_error(reserva)
    blocked_services = reserva.reserva_services.to_a.filter_map do |reserva_service|
      next if reserva_service.marked_for_destruction?
      next if service_holiday_block_exempt?(reserva_service.service)
      next unless service_holiday_block_candidate?(reserva_service)
      next unless ServicePurchaseDatePolicy.blocked_holiday_service_date?(reserva_service.service_date)

      service_name = reserva_service.service&.name.presence || 'Serviço'
      "#{service_name} em #{reserva_service.service_date.strftime('%d/%m/%Y')}"
    end

    return if blocked_services.blank?

    "#{ServicePurchaseDatePolicy.holiday_block_message} Datas bloqueadas: #{blocked_services.join(', ')}."
  end

  def service_holiday_block_candidate?(reserva_service)
    reserva_service.new_record? ||
      reserva_service.will_save_change_to_service_date? ||
      reserva_service.will_save_change_to_service_id?
  end

  def service_holiday_block_exempt?(service)
    return true if service.blank?

    CleaningServicesAssigner.cleaning_service?(service) ||
      ReservaService.free_date_service?(service) ||
      service.hidden_from_guests?
  end

  def sync_all_reservas_to_sheets
    return unless GoogleSheetsExportService.configured?

    GoogleSheetsExportService.export_reservas(
      Reserva.includes(:cabana, :user, reserva_services: :service).order(created_at: :desc)
    )
  end

  def summary_ransack_params
    return {} unless params[:q].present?

    params.require(:q).permit(:payment_status_eq)
  end

  def apply_general_search(scope)
    search = params[:search].to_s.squish
    return scope if search.blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(search.downcase)}%"
    scope.left_joins(:user, :cabana)
         .where(
           <<~SQL.squish,
             LOWER(CAST(reservas.id AS VARCHAR)) LIKE :term OR
             LOWER(COALESCE(users.name, '')) LIKE :term OR
             LOWER(COALESCE(users.email, '')) LIKE :term OR
             LOWER(COALESCE(users.telephone, '')) LIKE :term OR
             LOWER(COALESCE(cabanas.name, '')) LIKE :term OR
             LOWER(COALESCE(reservas.observation, '')) LIKE :term OR
             LOWER(COALESCE(reservas.origem, '')) LIKE :term OR
             LOWER(COALESCE(reservas.guest_name, '')) LIKE :term OR
             LOWER(COALESCE(reservas.guest_phone, '')) LIKE :term OR
             LOWER(COALESCE(reservas.guest_email, '')) LIKE :term
           SQL
           term: term
         )
  end

  def set_reserva
    @reserva = Reserva.find(params[:id])
  end

  def pending_service_payment_items
    CartItem.includes(:service)
            .where(reserva_id: @reserva.id, payment_status: 'waiting_payment')
            .where.not(payment_order_code: nil)
            .order(:payment_order_code, :service_date, :id)
  end

  def service_payment_sync_flash_for(result)
    if result.paid.positive?
      { notice: 'Pagamento de serviço confirmado na Cielo e lançado na reserva.' }
    elsif result.respond_to?(:late_paid) && result.late_paid.positive?
      { alert: 'A Cielo informou pagamento após vencimento em um link de reserva. A reserva não foi reativada automaticamente.' }
    elsif result.refused.positive?
      { alert: 'A Cielo informou pagamento recusado.' }
    elsif result.canceled.positive?
      { alert: 'A Cielo informou pagamento cancelado.' }
    elsif result.errors.positive?
      { alert: 'A Cielo ainda não retornou esse pagamento. Tente novamente em alguns minutos.' }
    else
      { notice: 'A Cielo ainda mostra este pagamento como aguardando.' }
    end
  end

  def service_purchase_override_deadline_param
    return if params[:service_purchase_override_until].blank?

    Date.iso8601(params[:service_purchase_override_until].to_s)
  rescue ArgumentError
    nil
  end

 
  def reserva_params
    params.require(:reserva).permit(
      :cabana_id, 
      :user_id, 
      :start_date, 
      :end_date, 
      :early_checkin,
      :late_checkout,
      :total_price, 
      :observation,
      :group_created,
      :guest_name,
      :guest_phone,
      :guest_email,
      user_attributes: [:id, :partner],
      reserva_services_attributes: [:id, :service_id, :quantity, :service_date, :status, :observation, :_destroy]
    )
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :name, :telephone, :partner)
  end

  def operations_viewer_allowed_action?
    !current_user&.operations_viewer? || OPERATIONS_VIEWER_ACTIONS.include?(action_name)
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
