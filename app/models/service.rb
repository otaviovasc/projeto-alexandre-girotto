class Service < ApplicationRecord
  PORTAL_CATEGORY_ORDER = [
    "Refeições",
    "Passeios",
    "Relaxamento",
    "Decorações e surpresas",
    "Outros"
  ].freeze

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

  def portal_category
    normalized_name = name.to_s.parameterize

    return "Refeições" if normalized_name.match?(/almoco|jantar|cafe-da-manha|piquenique|tabua.*frio|fondue/)
    return "Passeios" if normalized_name.match?(/trilha|cavalo|bicicleta|mountain-?bike/)
    return "Relaxamento" if normalized_name.include?("massagem")
    return "Decorações e surpresas" if normalized_name.match?(/decoracao|petala|luzinha|espumante|foto.*impress/)

    "Outros"
  end

  def portal_people_label
    normalized_name = name.to_s.parameterize
    return if normalized_name.match?(/petala|luzinha|espumante|foto.*impress/)

    if normalized_name.include?("massagem")
      return "Para 2 pessoas" if normalized_name.match?(/duas-pessoas|2-pessoas|casal/)

      return "Para 1 pessoa"
    end

    "Para até 2 pessoas"
  end

  def portal_region
    filial_name = filial&.name.to_s.parameterize
    return "SP" if filial_name.include?("brauna")
    return "MG" if filial_name.match?(/serra|mantiqueira/)

    filial&.region.presence || region
  end

  def photo_print_service?
    name.to_s.parameterize.match?(/foto.*impress/)
  end

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "description", "duration", "end_time", "filial_id", "id", "name", "partner_price", "price", "region", "show_in_marketplace", "start_time", "updated_at", "user_id"]
  end

  private

  def default_partner_price
    self.partner_price = price if partner_price.nil?
  end
end
