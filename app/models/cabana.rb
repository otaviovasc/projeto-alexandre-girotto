class Cabana < ApplicationRecord
  belongs_to :filial
  has_many :reservas
  has_many :info_da_cabanas, dependent: :destroy
  has_many :price_rules, dependent: :destroy

  has_many_attached :images

  validates :name, :price, presence: true
end
