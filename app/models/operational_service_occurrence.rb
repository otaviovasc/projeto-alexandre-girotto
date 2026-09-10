class OperationalServiceOccurrence < ApplicationRecord
  belongs_to :cabana
  belongs_to :filial

  enum status: {
    active: 'active',
    cancelled: 'cancelled'
  }

  validates :stable_id, :kind, :event_type, :name, :service_date, presence: true
  validates :stable_id, uniqueness: true

  scope :fake_holmy_cleaning, -> { where(kind: FakeHolmyCleaningSync::KIND) }
  scope :exportable, lambda {
    where(status: 'active').where('service_date >= ?', Date.current)
      .or(where(status: 'cancelled').where('service_date >= ?', Date.current - 30.days))
  }

  def cancel!(reason:)
    update!(
      status: 'cancelled',
      cancelled_at: Time.current,
      cancellation_reason: reason
    )
  end
end
