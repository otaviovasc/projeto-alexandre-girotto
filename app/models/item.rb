class Item < ApplicationRecord
  belongs_to :filial

  CATEGORIES = %w[Limpeza Comida Outro]

  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :category, presence: true, inclusion: { in: CATEGORIES }

  has_one_attached :image
end
