require 'digest'

class Api::QuotesController < ActionController::API
  before_action :authenticate_quote_token!, if: :quote_token_configured?
  after_action :allow_public_cors

  def show
    quote = OfficialQuoteApi.new(
      destino: params[:destino] || params[:filial],
      checkin: params[:checkin] || params[:start_date],
      checkout: params[:checkout] || params[:end_date],
      cabana: params[:cabana],
      details: params[:detalhes] || params[:details]
    ).call

    render json: quote
  rescue OfficialQuoteApi::Error => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  rescue OfficialSitePricing::Error => e
    render json: { ok: false, error: e.message }, status: :service_unavailable
  end

  def options
    head :ok
  end

  private

  def authenticate_quote_token!
    request_token = bearer_token.presence || params[:token].to_s

    return if secure_token_match?(request_token, quote_token)

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end

  def quote_token_configured?
    quote_token.present?
  end

  def quote_token
    ENV['AI_QUOTE_TOKEN'].to_s
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
    response.set_header('Access-Control-Allow-Origin', '*')
    response.set_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
    response.set_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
  end
end
