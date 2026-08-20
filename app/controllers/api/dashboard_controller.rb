require 'digest'

class Api::DashboardController < ActionController::API
  before_action :authenticate_dashboard_token!

  def unfinished_reservations
    reservas = Reserva.unfinished_pre_reservations
                      .includes(cabana: :filial)
                      .order(canceled_at: :desc, updated_at: :desc)

    rows = reservas.map { |reserva| unfinished_reservation_payload(reserva) }

    render json: {
      generated_at: Time.current.iso8601,
      source: 'villaggio-stock',
      count: rows.size,
      total_value: rows.sum { |row| row[:value].to_f },
      rows: rows
    }
  end

  private

  def authenticate_dashboard_token!
    configured_token = ENV['DASHBOARD_API_TOKEN'].to_s
    request_token = bearer_token.presence || params[:token].to_s

    return if secure_token_match?(request_token, configured_token)

    render json: { error: 'unauthorized' }, status: :unauthorized
  end

  def bearer_token
    request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
  end

  def secure_token_match?(request_token, configured_token)
    return false if request_token.blank? || configured_token.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(request_token),
      Digest::SHA256.hexdigest(configured_token)
    )
  end

  def unfinished_reservation_payload(reserva)
    cabana = reserva.cabana
    filial = cabana&.filial
    reference_time = reserva.canceled_at || reserva.updated_at

    {
      id: reserva.id,
      date: dashboard_date(reference_time),
      date_time: dashboard_datetime(reference_time),
      start_date: reserva.start_date&.iso8601,
      end_date: reserva.end_date&.iso8601,
      cabin: cabana&.name.to_s,
      branch: filial&.name.to_s,
      value: reserva.total_price.to_f
    }
  end

  def dashboard_date(value)
    value&.in_time_zone('America/Sao_Paulo')&.to_date&.iso8601
  end

  def dashboard_datetime(value)
    value&.in_time_zone('America/Sao_Paulo')&.iso8601
  end
end
