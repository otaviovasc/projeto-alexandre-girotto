class FnrhEvent < ApplicationRecord
  belongs_to :reserva

  validates :event_type, :source, :status, :occurred_at, presence: true

  scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }
end
