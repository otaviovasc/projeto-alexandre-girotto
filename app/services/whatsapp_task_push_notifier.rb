require 'web_push'

class WhatsappTaskPushNotifier
  DEFAULT_TARGET_URL = 'https://villaggio-stock.onrender.com/admin/mensagens_whatsapp'.freeze

  Result = Struct.new(:sent, :failed, :message, keyword_init: true)

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
    return Result.new(sent: 0, failed: 0, message: 'Web Push não configurado') unless configured?

    sent = 0
    failed = 0

    target_subscriptions.find_each do |subscription|
      send_subscription(subscription)
      sent += 1
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription => e
      subscription.update_columns(active: false, updated_at: Time.current)
      failed += 1
      Rails.logger.warn("Push WhatsApp desativado para subscription #{subscription.id}: #{e.message}")
    rescue => e
      failed += 1
      Rails.logger.warn("Push WhatsApp não enviado para subscription #{subscription.id}: #{e.message}")
    end

    Result.new(sent: sent, failed: failed, message: "#{sent} enviado(s), #{failed} falha(s)")
  end

  private

  def configured?
    ENV['WEB_PUSH_PUBLIC_KEY'].present? && ENV['WEB_PUSH_PRIVATE_KEY'].present?
  end

  def target_subscriptions
    WebPushSubscription
      .active
      .joins(:user)
      .merge(User.operations_viewers)
  end

  def send_subscription(subscription)
    WebPush.payload_send(
      message: payload.to_json,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      vapid: {
        subject: ENV.fetch('WEB_PUSH_SUBJECT', 'mailto:contato@villaggiogirotto.com.br'),
        public_key: ENV['WEB_PUSH_PUBLIC_KEY'],
        private_key: ENV['WEB_PUSH_PRIVATE_KEY']
      },
      ttl: 86_400
    )
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
