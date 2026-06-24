class FnrhPortalController < ApplicationController
  layout 'fnrh_portal'
  skip_before_action :authenticate_user!

  def index
  end

  def access
    reserva = Reserva.includes(:user, cabana: :filial).find_by(id: params[:reservation_code].to_i)

    unless reservation_matches?(reserva, params[:guest_name])
      redirect_to fnrh_portal_path, alert: 'Reserva não encontrada. Confira o nome e o código informados.'
      return
    end

    if reserva.canceled? || reserva.fnrh_status == 'cancelled'
      redirect_to fnrh_portal_path, alert: 'Esta reserva está cancelada.'
      return
    end

    unless reserva.fnrh_eligible?
      redirect_to fnrh_portal_path, alert: 'Seu acesso ao pré-check-in ainda está sendo preparado. Tente novamente em alguns minutos.'
      return
    end

    if reserva.fnrh_reservation_id.blank?
      synced = Fnrh::ReservationSyncService.new(reserva, source: 'guest_portal').call
      reserva.reload

      unless synced && reserva.fnrh_precheckin_url.present?
        redirect_to fnrh_portal_path, alert: 'Não foi possível preparar o pré-check-in agora. Tente novamente em alguns minutos.'
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

  def reservation_matches?(reserva, identifier)
    return false unless reserva

    normalized = I18n.transliterate(identifier.to_s).downcase.squish
    user = reserva.user
    candidates = [user.name, user.name.to_s.split.first, user.email].map do |value|
      I18n.transliterate(value.to_s).downcase.squish
    end

    normalized.present? && candidates.include?(normalized)
  end
end
