require "digest"

class Api::AnalyticsController < ActionController::API
  before_action :authenticate_dashboard_token!, except: :options
  after_action :allow_public_cors

  def service_purchase_funnel
    scope = GuestPortalEvent.where(event_name: GuestPortalEvent::SERVICE_PURCHASE_FUNNEL_EVENTS)
    scope = scope.where(occurred_at: start_time..) if start_time.present?
    scope = scope.where(occurred_at: ..end_time) if end_time.present?

    opened_scope = scope.where(event_name: GuestPortalEvent::OPENED_SERVICES_PAGE)
    added_scope = scope.where(event_name: GuestPortalEvent::ADDED_SERVICE_TO_CART)
    opened_unique = opened_scope.distinct.count(:reserva_id)
    added_unique = added_scope.distinct.count(:reserva_id)

    render json: {
      ok: true,
      generated_at: Time.current.iso8601,
      source: "villaggio-stock",
      filters: {
        start_date: parsed_start_date&.iso8601,
        end_date: parsed_end_date&.iso8601
      },
      opened_services_page_unique_reservas: opened_unique,
      added_service_to_cart_unique_reservas: added_unique,
      opened_services_page_events: opened_scope.count,
      added_service_to_cart_events: added_scope.count,
      added_from_opened_rate: rate(added_unique, opened_unique),
      events: {
        GuestPortalEvent::OPENED_SERVICES_PAGE => {
          unique_reservas: opened_unique,
          total_events: opened_scope.count
        },
        GuestPortalEvent::ADDED_SERVICE_TO_CART => {
          unique_reservas: added_unique,
          total_events: added_scope.count
        }
      }
    }
  end

  def options
    head :ok
  end

  private

  def parsed_start_date
    @parsed_start_date ||= parse_date_param(params[:start_date])
  end

  def parsed_end_date
    @parsed_end_date ||= parse_date_param(params[:end_date])
  end

  def start_time
    parsed_start_date&.beginning_of_day
  end

  def end_time
    parsed_end_date&.end_of_day
  end

  def parse_date_param(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    ((numerator.to_f / denominator.to_f) * 100).round(2)
  end

  def authenticate_dashboard_token!
    configured_token = ENV["DASHBOARD_API_TOKEN"].to_s
    request_token = bearer_token.presence || params[:token].to_s

    return if secure_token_match?(request_token, configured_token)

    render json: { ok: false, error: "unauthorized" }, status: :unauthorized
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

  def allow_public_cors
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Methods", "GET, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
  end
end
