class ReservaService < ApplicationRecord
  belongs_to :reserva
  belongs_to :service

  enum status: {
    active: 'active',
    cancelled: 'cancelled',
    pending_portal: 'pending_portal',
    pending_payment: 'pending_payment'
  }

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :service_date, presence: true

  scope :active_services, -> { where(status: 'active') }
  scope :cancelled_services, -> { where(status: 'cancelled') }

  def cancel!
    update!(status: 'cancelled')
  end
end
