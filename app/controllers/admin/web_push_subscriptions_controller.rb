class Admin::WebPushSubscriptionsController < ApplicationController
  before_action :authorize_admin_or_operations_viewer

  def create
    return render json: { ok: false, error: 'not_allowed' }, status: :forbidden unless current_user.operations_viewer?

    subscription_params = params.require(:subscription)
    keys = subscription_params[:keys] || subscription_params['keys'] || {}

    subscription = WebPushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint].to_s)
    subscription.assign_attributes(
      user: current_user,
      p256dh: keys[:p256dh].to_s.presence || keys['p256dh'].to_s,
      auth: keys[:auth].to_s.presence || keys['auth'].to_s,
      user_agent: request.user_agent.to_s.truncate(500),
      active: true,
      last_seen_at: Time.current
    )
    subscription.save!

    render json: { ok: true }
  rescue ActionController::ParameterMissing
    render json: { ok: false, error: 'subscription_missing' }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end
end
