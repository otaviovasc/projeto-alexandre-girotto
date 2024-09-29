class ReservaItem < ApplicationRecord
  belongs_to :reserva
  belongs_to :item

  validates :quantity, presence: true, numericality: { greater_than: 0 }
end
