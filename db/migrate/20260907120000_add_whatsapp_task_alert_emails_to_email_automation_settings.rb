class AddWhatsappTaskAlertEmailsToEmailAutomationSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :email_automation_settings, :whatsapp_task_alert_email_1, :string
    add_column :email_automation_settings, :whatsapp_task_alert_email_2, :string
  end
end
