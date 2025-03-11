class Promotion < ApplicationRecord
  belongs_to :cabana

  # Atributo virtual para controlar o tipo de promoção (checkbox no formulário)
  attr_accessor :is_interval

  # Validações aplicáveis somente para promoções de data única
  validates :date, presence: true, uniqueness: { scope: :cabana_id, message: "já possui promoção cadastrada para essa data" }, unless: :interval_promotion?

  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Validação personalizada somente para promoções de intervalo
  validate :validate_interval_dates, if: :interval_promotion?

  def validate_interval_dates
    if start_date.blank? || end_date.blank?
      errors.add(:base, "Para promoções de intervalo, as datas de início e término são obrigatórias")
    elsif start_date > end_date
      errors.add(:base, "A data de início deve ser anterior à data de término")
    end
  end

  # Método auxiliar que indica se é promoção de intervalo
  def interval_promotion?
    is_interval == "1"
  end
end
