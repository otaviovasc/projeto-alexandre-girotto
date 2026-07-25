class FnrhPortalController < ApplicationController
  TERMS_VERSION = '2026-07-16'.freeze
  AUTO_BYPASS_PRECHECKIN_AFTER = 3.minutes

  layout 'fnrh_portal'
  skip_before_action :authenticate_user!

  def index
  end

  def terms
    @reserva = terms_portal_reserva

    if @reserva
      remember_terms_reservation(@reserva)
      @terms_accepted = terms_already_accepted?(@reserva)
      @guest_name = session[:fnrh_terms_guest_name].presence || guest_identifier_for(@reserva)
      refresh_fnrh_release_status(@reserva) if @terms_accepted
      @reserva.reload
      @precheckin_link_opened = precheckin_link_already_opened?(@reserva)
    end
  end

  def access
    process_reservation_access(
      failure_path: fnrh_portal_path,
      record_terms: false
    )
  end

  def terms_access
    reserva = find_reservation_for_terms_access
    return unless reserva

    remember_terms_reservation(reserva)

    if terms_already_accepted?(reserva)
      session.delete(:pending_terms_reserva_id)
      redirect_to fnrh_terms_path
      return
    end

    unless params.key?(:terms_accepted)
      session[:pending_terms_reserva_id] = reserva.id
      redirect_to fnrh_terms_path
      return
    end

    unless ActiveModel::Type::Boolean.new.cast(params[:terms_accepted])
      session[:pending_terms_reserva_id] = reserva.id
      redirect_to fnrh_terms_path, alert: 'Leia e confirme os termos para liberar o acesso da reserva.'
      return
    end

    record_terms_accepted(reserva)
    session.delete(:pending_terms_reserva_id)
    redirect_to fnrh_terms_path, notice: 'Termos aceitos. Acesso liberado.'
  end

  def orientation
    @reserva = portal_reserva
    redirect_to fnrh_portal_path, alert: 'Informe os dados da sua reserva para iniciar o pré-check-in.' and return unless @reserva

    refresh_fnrh_release_status(@reserva)
    @reserva.reload

    redirect_to fnrh_portal_information_path if @reserva.fnrh_information_released?
  end

  def start_precheckin
    @reserva = portal_reserva
    redirect_to fnrh_portal_path, alert: 'Informe os dados da sua reserva para iniciar o pré-check-in.' and return unless @reserva

    refresh_fnrh_release_status(@reserva)
    @reserva.reload

    if @reserva.fnrh_information_released?
      redirect_to fnrh_portal_information_path
    elsif @reserva.fnrh_precheckin_url.present?
      record_precheckin_link_opened(@reserva) unless precheckin_link_already_opened?(@reserva)
      redirect_to @reserva.fnrh_precheckin_url, allow_other_host: true
    else
      redirect_to fnrh_portal_path, alert: 'Não foi possível abrir o pré-check-in agora. Tente novamente em alguns minutos.'
    end
  end

  def waiting
    @reserva = portal_reserva
    redirect_to fnrh_portal_path, alert: 'Informe os dados da sua reserva para acompanhar o pré-check-in.' and return unless @reserva

    refresh_fnrh_release_status(@reserva)
    @reserva.reload

    redirect_to fnrh_portal_information_path if @reserva.fnrh_information_released?
  end

  def verify
    @reserva = portal_reserva
    redirect_to fnrh_portal_path, alert: 'Informe os dados da sua reserva para verificar o pré-check-in.' and return unless @reserva

    refresh_fnrh_release_status(@reserva)
    @reserva.reload

    if @reserva.fnrh_information_released?
      redirect_to fnrh_portal_information_path, notice: 'Pré-check-in confirmado.'
    else
      redirect_to fnrh_portal_waiting_path, alert: 'Ainda não recebemos a confirmação da FNRH. Tente novamente em alguns minutos.'
    end
  end

  def information
    @reserva = portal_reserva
    refresh_fnrh_release_status(@reserva) if @reserva
    @reserva&.reload
    return if @reserva&.fnrh_information_released?

    session.delete(:fnrh_portal_reserva_id)
    redirect_to fnrh_portal_path, alert: 'Conclua o pré-check-in para acessar as informações da hospedagem.'
  end

  def logout
    session.delete(:fnrh_portal_reserva_id)
    session.delete(:portal_reserva_id)
    session.delete(:pending_terms_reserva_id)
    session.delete(:fnrh_terms_guest_name)
    redirect_to fnrh_terms_path
  end

  private

  def find_reservation_for_terms_access
    if params[:guest_name].to_s.match?(/\s/)
      redirect_to fnrh_terms_path, alert: 'Digite somente o primeiro nome, sem espaços.'
      return
    end

    reserva = Reserva.includes(:user, :fnrh_events, cabana: :filial).find_by(id: params[:reservation_code].to_i)

    unless reservation_matches?(reserva, params[:guest_name])
      redirect_to fnrh_terms_path, alert: 'Reserva não encontrada. Confira o primeiro nome e o código informados.'
      return
    end

    if reserva.canceled? || reserva.fnrh_status == 'cancelled'
      redirect_to fnrh_terms_path, alert: 'Esta reserva está cancelada.'
      return
    end

    reserva
  end

  def terms_portal_reserva
    reserva_id = session[:pending_terms_reserva_id].presence ||
                 session[:fnrh_portal_reserva_id].presence ||
                 session[:portal_reserva_id].presence

    return if reserva_id.blank?

    Reserva.includes(:user, :fnrh_events, cabana: :filial).find_by(id: reserva_id)
  end

  def remember_terms_reservation(reserva)
    session[:fnrh_portal_reserva_id] = reserva.id
    session[:portal_reserva_id] = reserva.id
    session[:fnrh_terms_guest_name] = params[:guest_name].presence || session[:fnrh_terms_guest_name].presence || guest_identifier_for(reserva)
  end

  def terms_already_accepted?(reserva)
    reserva.fnrh_events.where(event_type: 'terms_accepted').exists?
  end

  def guest_identifier_for(reserva)
    reserva.guest_name.to_s.squish.split.first.presence ||
      reserva.user&.name.to_s.squish.split.first.presence ||
      reserva.user&.email.to_s
  end

  def process_reservation_access(failure_path:, record_terms:)
    if params[:guest_name].to_s.match?(/\s/)
      redirect_to failure_path, alert: 'Digite somente o primeiro nome, sem espaços.'
      return
    end

    reserva = Reserva.includes(:user, cabana: :filial).find_by(id: params[:reservation_code].to_i)

    unless reservation_matches?(reserva, params[:guest_name])
      redirect_to failure_path, alert: 'Reserva não encontrada. Confira o nome e o código informados.'
      return
    end

    if reserva.canceled? || reserva.fnrh_status == 'cancelled'
      redirect_to failure_path, alert: 'Esta reserva está cancelada.'
      return
    end

    record_terms_accepted(reserva) if record_terms

    if reserva.fnrh_information_released?
      session[:fnrh_portal_reserva_id] = reserva.id
      redirect_to fnrh_portal_information_path
      return
    end

    unless reserva.fnrh_eligible?
      redirect_to failure_path, alert: 'Seu acesso ao pré-check-in ainda está sendo preparado. Tente novamente em alguns minutos.'
      return
    end

    if reserva.fnrh_reservation_id.blank?
      synced = Fnrh::ReservationSyncService.new(reserva, source: 'guest_portal').call
      reserva.reload

      unless synced && reserva.fnrh_precheckin_url.present?
        redirect_to failure_path, alert: 'Não foi possível preparar o pré-check-in agora. Tente novamente em alguns minutos.'
        return
      end
    end

    session[:fnrh_portal_reserva_id] = reserva.id
    refresh_fnrh_release_status(reserva)
    reserva.reload

    if reserva.fnrh_information_released?
      redirect_to fnrh_portal_information_path
    elsif precheckin_link_already_opened?(reserva)
      redirect_to fnrh_portal_waiting_path
    else
      redirect_to fnrh_portal_orientation_path
    end
  end

  def portal_reserva
    Reserva.includes(:user, :fnrh_events, cabana: :filial).find_by(id: session[:fnrh_portal_reserva_id])
  end

  def precheckin_link_already_opened?(reserva)
    reserva.fnrh_events.where(event_type: 'precheckin_link_opened').exists?
  end

  def record_precheckin_link_opened(reserva)
    reserva.fnrh_events.create!(
      event_type: 'precheckin_link_opened',
      source: 'guest_portal',
      status: 'success',
      message: 'Hóspede enviado ao link oficial de pré-check-in',
      occurred_at: Time.current
    )
  end

  def refresh_fnrh_release_status(reserva)
    return true if reserva.fnrh_information_released?
    return false unless reserva.fnrh_reservation_id.present?

    Fnrh::PrecheckinStatusSyncService.new(reserva, source: 'guest_portal').call
    reserva.reload
    return true if reserva.fnrh_information_released?

    auto_bypass_stale_precheckin(reserva)
  end

  def auto_bypass_stale_precheckin(reserva)
    return false unless reserva.fnrh_status == 'awaiting_precheckin'

    opened_at = precheckin_link_opened_at(reserva)
    return false if opened_at.blank? || opened_at > AUTO_BYPASS_PRECHECKIN_AFTER.ago

    Fnrh::TransitionService.new(reserva, source: 'automatic_guest_portal').bypass_precheckin(
      message: 'FNRH pulada automaticamente após pré-check-in ficar pendente por mais de 3 minutos',
      metadata: {
        internal_release: true,
        automatic_after_pending_precheckin: true,
        precheckin_link_opened_at: opened_at
      }
    )
  rescue => e
    Rails.logger.warn("Erro ao pular FNRH automaticamente para reserva ##{reserva.id}: #{e.message}")
    false
  end

  def precheckin_link_opened_at(reserva)
    reserva.fnrh_events
           .where(event_type: 'precheckin_link_opened')
           .order(:occurred_at)
           .pick(:occurred_at)
  end

  def record_terms_accepted(reserva)
    reserva.fnrh_events.create!(
      event_type: 'terms_accepted',
      source: 'terms_portal',
      status: 'success',
      message: 'Hóspede confirmou leitura dos termos e condições',
      metadata: {
        terms_version: TERMS_VERSION,
        ip: request.remote_ip,
        user_agent: request.user_agent.to_s[0, 300]
      },
      occurred_at: Time.current
    )
  end

  def reservation_matches?(reserva, identifier)
    return false unless reserva

    reserva.matches_reservation_identifier?(identifier)
  end
end
