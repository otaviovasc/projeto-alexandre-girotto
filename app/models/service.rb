class Service < ApplicationRecord
  belongs_to :filial
  belongs_to :user
  has_many :reserva_services
  has_many :reservas, through: :reserva_services

  has_many_attached :images

  before_validation :default_partner_price

  validates :name, :price, :partner_price, presence: true
  validates :price, :partner_price, numericality: { greater_than_or_equal_to: 0 }
  validates :region, inclusion: { in: %w[SP MG], message: 'deve ser SP ou MG' }, allow_blank: true

  # Regiões disponíveis
  REGIONS = [['São Paulo (SP)', 'SP'], ['Minas Gerais (MG)', 'MG']].freeze

  def price_for(reserva)
    return price unless reserva&.partnership_reservation?

    partner_price || price
  end

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "description", "duration", "end_time", "filial_id", "id", "name", "partner_price", "price", "region", "show_in_marketplace", "start_time", "updated_at", "user_id"]
  end

  private

  def default_partner_price
    self.partner_price = price if partner_price.nil?
  end
end
