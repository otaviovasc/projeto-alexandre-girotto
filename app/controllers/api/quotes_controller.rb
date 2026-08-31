require 'digest'

class Api::QuotesController < ActionController::API
  before_action :authenticate_quote_token!, if: :quote_token_configured?
  after_action :allow_public_cors

  def show
    render json: OfficialQuoteApi.new(params: params).call
  rescue OfficialQuoteApi::Error => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  rescue OfficialSitePricing::Error => e
    render json: { ok: false, error: e.message }, status: :service_unavailable
  rescue => e
    Rails.logger.warn("Unable to load official quote API: #{e.class} - #{e.message}")
    render json: { ok: false, error: 'Nao foi possivel carregar a cotacao.' }, status: :service_unavailable
  end

  def options
    head :ok
  end

  private

  def allow_public_cors
    response.set_header('Access-Control-Allow-Origin', '*')
    response.set_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
    response.set_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
  end

  def quote_token_configured?
    ENV['AI_QUOTE_TOKEN'].present?
  end

  def authenticate_quote_token!
    expected = ENV['AI_QUOTE_TOKEN'].to_s
    provided = request.headers['Authorization'].to_s.delete_prefix('Bearer ').presence || params[:token].to_s

    return if provided.present? && secure_compare(provided, expected)

    render json: { ok: false, error: 'Nao autorizado.' }, status: :unauthorized
  end

  def secure_compare(provided, expected)
    Digest::SHA256.hexdigest(provided) == Digest::SHA256.hexdigest(expected) &&
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
