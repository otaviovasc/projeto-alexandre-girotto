class FnrhPortalController < ApplicationController
  layout 'fnrh_portal'
  skip_before_action :authenticate_user!

  def index
  end

  def terms
  end

  def access
    process_reservation_access(
      failure_path: fnrh_portal_path,
      record_terms: false
    )
  end

  def terms_access
    process_reservation_access(
      failure_path: fnrh_terms_path,
      record_terms: true
    )
  end

  def orientation
    @reserva = portal_reserva
    redirect_to fnrh_portal_path, alert: 'Informe os dados da sua reserva para iniciar o pré-check-in.' and return unless @reserva

    Fnrh::PrecheckinStatusSyncService.new(@reserva, source: 'guest_portal').call
    @reserva.reload

    redirect_to fnrh_portal_information_path if @reserva.fnrh_information_released?
  end

  def start_precheckin
    @reserva = portal_reserva
    redirect_to fnrh_portal_path, alert: 'Informe os dados da sua reserva para iniciar o pré-check-in.' and return unless @reserva

    Fnrh::PrecheckinStatusSyncService.new(@reserva, source: 'guest_portal').call
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

    Fnrh::PrecheckinStatusSyncService.new(@reserva, source: 'guest_portal').call
    @reserva.reload

    redirect_to fnrh_portal_information_path if @reserva.fnrh_information_released?
  end

  def verify
    @reserva = portal_reserva
    redirect_to fnrh_portal_path, alert: 'Informe os dados da sua reserva para verificar o pré-check-in.' and return unless @reserva

    Fnrh::PrecheckinStatusSyncService.new(@reserva, source: 'guest_portal').call
    @reserva.reload

    if @reserva.fnrh_information_released?
      redirect_to fnrh_portal_information_path, notice: 'Pré-check-in confirmado.'
    else
      redirect_to fnrh_portal_waiting_path, alert: 'Ainda não recebemos a confirmação da FNRH. Tente novamente em alguns minutos.'
    end
  end

  def information
    @reserva = portal_reserva
    return if @reserva&.fnrh_information_released?

    session.delete(:fnrh_portal_reserva_id)
    redirect_to fnrh_portal_path, alert: 'Conclua o pré-check-in para acessar as informações da hospedagem.'
  end

  def logout
    session.delete(:fnrh_portal_reserva_id)
    redirect_to fnrh_portal_path
  end

  private

  def process_reservation_access(failure_path:, record_terms:)
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
    Fnrh::PrecheckinStatusSyncService.new(reserva, source: 'guest_portal').call
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

  def record_terms_accepted(reserva)
    reserva.fnrh_events.create!(
      event_type: 'terms_accepted',
      source: 'terms_portal',
      status: 'success',
      message: 'Hóspede confirmou leitura dos termos e condições',
      metadata: {
        ip: request.remote_ip,
        user_agent: request.user_agent.to_s[0, 300]
      },
      occurred_at: Time.current
    )
  end

  def reservation_matches?(reserva, identifier)
    return false unless reserva

    reserva.user.matches_reservation_identifier?(identifier)
  end
end
