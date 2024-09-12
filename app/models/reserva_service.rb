class ReservaService < ApplicationRecord
  belongs_to :reserva
  belongs_to :service

  validates :quantity, presence: true, numericality: { greater_than: 0 }
end
