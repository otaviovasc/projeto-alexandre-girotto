class IcalReservationChange < ApplicationRecord
  belongs_to :reserva

  validates :platform, presence: true
  validates :old_start_date, :old_end_date, :new_start_date, :new_end_date, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  def acknowledged?
    acknowledged_at.present?
  end
end
