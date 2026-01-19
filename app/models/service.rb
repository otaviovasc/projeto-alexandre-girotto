class Service < ApplicationRecord
  belongs_to :filial
  belongs_to :user
  has_many :reserva_services
  has_many :reservas, through: :reserva_services

  has_many_attached :images

  validates :name, :price, presence: true
  validates :region, inclusion: { in: %w[SP MG], message: 'deve ser SP ou MG' }, allow_blank: true

  # Regiões disponíveis
  REGIONS = [['São Paulo (SP)', 'SP'], ['Minas Gerais (MG)', 'MG']].freeze

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "description", "duration", "end_time", "filial_id", "id", "name", "price", "region", "show_in_marketplace", "start_time", "updated_at", "user_id"]
  end
end
