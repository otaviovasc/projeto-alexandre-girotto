class Service < ApplicationRecord
  belongs_to :filial
  belongs_to :user
  has_many :reserva_services
  has_many :reservas, through: :reserva_services

  has_many_attached :images

  validates :name, :price, presence: true
end
