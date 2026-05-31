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

  before_save :mark_manual_date_override, if: :cleaning_service?
  after_save :ensure_cleaning_pair, if: :cleaning_service?

  scope :active_services, -> { where(status: 'active') }
  scope :cancelled_services, -> { where(status: 'cancelled') }

  def cancel!
    update!(status: 'cancelled')
  end

  private

  def cleaning_service?
    CleaningServicesAssigner.cleaning_service?(service)
  end

  def mark_manual_date_override
    return unless respond_to?(:manual_date_override=)

    expected_date = CleaningServicesAssigner.expected_date_for(reserva, service)
    self.manual_date_override = expected_date.present? &&
                                service_date.present? &&
                                service_date != expected_date
  end

  def ensure_cleaning_pair
    CleaningServicesAssigner.new(reserva).call
  end
end
