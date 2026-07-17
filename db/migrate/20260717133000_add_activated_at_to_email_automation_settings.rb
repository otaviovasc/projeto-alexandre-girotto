class AddActivatedAtToEmailAutomationSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :email_automation_settings, :activated_at, :datetime
  end
end
