class Api::ServicesController < ActionController::API
  after_action :allow_public_cors

  def index
    render json: {
      ok: true,
      generated_at: Time.current.iso8601,
      fonte: 'Render',
      servicos: OfficialServicesCatalog.new.all
    }
  rescue => e
    Rails.logger.warn("Unable to load official services catalog: #{e.message}")
    render json: { ok: false, error: 'Nao foi possivel carregar os servicos.' }, status: :service_unavailable
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
end
