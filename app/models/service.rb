class Service < ApplicationRecord
  belongs_to :filial
  has_many :reserva_services
  has_many :reservas, through: :reserva_services

  validates :name, :price, presence: true
end
