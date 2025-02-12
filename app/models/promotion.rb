class Promotion < ApplicationRecord
  belongs_to :cabana

  # Garante que para cada cabana não haja duas promoções para a mesma data
  validates :date, presence: true, uniqueness: { scope: :cabana_id, message: "já possui promoção cadastrada para essa data" }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
