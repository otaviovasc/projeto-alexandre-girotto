class Cabana < ApplicationRecord
  BREAKFAST_SOURCE_COLUMNS = {
    'airbnb' => :breakfast_included_airbnb,
    'booking' => :breakfast_included_booking,
    'holmy' => :breakfast_included_holmy,
    'direct' => :breakfast_included_direct
  }.freeze

  BREAKFAST_SOURCE_LABELS = {
    'airbnb' => 'Airbnb',
    'booking' => 'Booking',
    'holmy' => 'Holmy',
    'direct' => 'Reservas diretas'
  }.freeze

  belongs_to :filial
  has_many :reservas, dependent: :destroy
  has_many :info_da_cabanas, dependent: :destroy
  has_many :price_rules, dependent: :destroy
  has_many :promotions, dependent: :destroy

  has_many_attached :images

  validates :name, :price, presence: true

  def self.breakfast_source_options
    BREAKFAST_SOURCE_COLUMNS.map do |source, column|
      [source, BREAKFAST_SOURCE_LABELS.fetch(source), column]
    end
  end

  def breakfast_included_for?(source)
    normalized_source = self.class.normalize_breakfast_source(source)
    column = BREAKFAST_SOURCE_COLUMNS[normalized_source]

    column.present? && public_send(column)
  end

  def guest_display_name
    base_name = name.to_s.split(' - ').first.to_s.squish
    normalized_name = I18n.transliterate(base_name).downcase

    return 'Casa de Campo Villa Vita' if normalized_name.include?('vita')

    "Cabana #{base_name}"
  end

  def self.normalize_breakfast_source(source)
    normalized = I18n.transliterate(source.to_s).downcase.squish

    return 'airbnb' if normalized.include?('airbnb')
    return 'booking' if normalized.include?('booking')
    return 'holmy' if normalized.include?('holmy')
    return 'direct' if normalized.in?(%w[sistema direct direto direta]) ||
                       normalized.include?('reserva direta') ||
                       normalized.include?('reservas diretas')

    normalized.presence
  end
end
