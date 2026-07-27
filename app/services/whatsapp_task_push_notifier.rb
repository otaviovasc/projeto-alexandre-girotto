require 'httparty'

class WhatsappTaskPushNotifier
  DEFAULT_ENDPOINT = 'https://organizacao-villaggio.web.app/api/send-external-push'.freeze
  DEFAULT_TARGET_URL = 'https://villaggio-stock.onrender.com/admin/mensagens_whatsapp'.freeze

  Result = Struct.new(:sent, :status, :message, keyword_init: true)

  def self.deliver(title:, body:, tag:, url: nil)
    new(title: title, body: body, tag: tag, url: url).deliver
  end

  def initialize(title:, body:, tag:, url:)
    @title = title
    @body = body
    @tag = tag
    @url = url.presence || ENV.fetch('WHATSAPP_TASKS_URL', DEFAULT_TARGET_URL)
  end

  def deliver
    return Result.new(sent: false, message: 'Endpoint de push não configurado') if endpoint.blank?
    return Result.new(sent: false, message: 'Token de push não configurado') if token.blank?

    response = HTTParty.post(
      endpoint,
      headers: {
        'Content-Type' => 'application/json',
        'X-Villaggio-Push-Token' => token
      },
      body: payload.to_json,
      timeout: 8
    )

    if response.success?
      Result.new(sent: true, status: response.code, message: response.body)
    else
      Result.new(sent: false, status: response.code, message: response.body)
    end
  rescue => e
    Result.new(sent: false, message: e.message)
  end

  private

  def endpoint
    ENV.fetch('WHATSAPP_PUSH_ENDPOINT', DEFAULT_ENDPOINT)
  end

  def token
    ENV['WHATSAPP_PUSH_TOKEN'].presence
  end

  def payload
    {
      title: @title,
      body: @body,
      tag: @tag,
      url: @url
    }
  end
end
