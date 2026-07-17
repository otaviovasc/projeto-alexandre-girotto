class EmailAutomationSetting < ApplicationRecord
  belongs_to :paused_by, class_name: 'User', optional: true

  def self.current
    first_or_create!(enabled: false)
  end

  def self.enabled?
    current.enabled?
  end

  def pause!(user = nil)
    update!(enabled: false, paused_at: Time.current, paused_by: user)
  end

  def resume!
    update!(enabled: true, paused_at: nil, paused_by: nil)
  end
end
