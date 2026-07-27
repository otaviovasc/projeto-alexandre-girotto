class WebPushSubscription < ApplicationRecord
  belongs_to :user

  scope :active, -> { where(active: true) }

  validates :endpoint, :p256dh, :auth, presence: true
end
