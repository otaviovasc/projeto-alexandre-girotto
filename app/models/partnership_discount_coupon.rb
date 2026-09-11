require 'bigdecimal'

class PartnershipDiscountCoupon < ApplicationRecord
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :reservas, dependent: :nullify

  before_validation :assign_normalized_code

  validates :code, presence: true, length: { maximum: 50 }
  validates :normalized_code, presence: true, uniqueness: true
  validates :discount_percent,
            presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  scope :active, -> { where(active: true) }

  def self.normalize_code(value)
    I18n.transliterate(value.to_s).upcase.gsub(/\s+/, '')
  end

  def self.find_active_by_code(value)
    active.find_by(normalized_code: normalize_code(value))
  end

  def discount_amount_for(amount)
    base = BigDecimal(amount.to_s.presence || '0')
    discount = base * BigDecimal(discount_percent.to_s) / 100
    [discount.round(2), base].min
  rescue ArgumentError, TypeError
    0.to_d
  end

  private

  def assign_normalized_code
    self.code = code.to_s.squish.upcase if code.present?
    self.normalized_code = self.class.normalize_code(code)
  end
end
