class GuestPortalEvent < ApplicationRecord
  OPENED_SERVICES_PAGE = "opened_services_page".freeze
  ADDED_SERVICE_TO_CART = "added_service_to_cart".freeze
  SERVICE_PURCHASE_FUNNEL_EVENTS = [
    OPENED_SERVICES_PAGE,
    ADDED_SERVICE_TO_CART
  ].freeze

  belongs_to :reserva

  validates :event_name, presence: true, inclusion: { in: SERVICE_PURCHASE_FUNNEL_EVENTS }
  validates :occurred_at, presence: true
end
