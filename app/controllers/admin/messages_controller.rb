class Admin::MessagesController < ApplicationController
  before_action :authorize_admin_or_operations_viewer

  def index
    @pending_whatsapp_count = ReservationWhatsappTask
                              .visible_on(Date.current)
                              .pending
                              .to_a
                              .select(&:active_for_whatsapp?)
                              .size
    @email_setting = EmailAutomationSetting.current if defined?(EmailAutomationSetting)
    @active_email_templates_count = ReservationEmailTemplate.active.count if defined?(ReservationEmailTemplate)
  end

  def operational_rules; end
end
