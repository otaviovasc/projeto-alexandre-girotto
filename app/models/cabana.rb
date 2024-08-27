class Cabana < ApplicationRecord
  belongs_to :filial
  has_many :reservas
  has_many :info_da_cabanas

  has_many_attached :images

  validates :name, :price, presence: true
end
