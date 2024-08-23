class Reserva < ApplicationRecord
  belongs_to :cabana
  belongs_to :user

  validate :start_date_cannot_be_in_the_past
  validate :end_date_after_start_date
  validate :dates_available

  before_save :calculate_total_price

  private

  def start_date_cannot_be_in_the_past
    if start_date.present? && start_date < Date.today
      errors.add(:start_date, "não pode estar no passado.")
    end
  end

  def end_date_after_start_date
    if end_date.present? && (end_date <= start_date)
      errors.add(:end_date, "deve ser após a data de início.")
    end
  end

  def dates_available
    unless available?(cabana, self)
      errors.add(:base, "A Cabana esta indisponível na data selecionada.")
    end
  end

  def calculate_total_price
    total_days = (end_date - start_date).to_i
    self.total_price = cabana.price * total_days
  end

  def available?(cabana, reserva)
    new_reserva_range = reserva.start_date..reserva.end_date
    existing_reservas = Reserva.where(cabana_id: cabana.id)
    existing_reservas.each do |existing_reserva|
      existing_reserva_range = existing_reserva.start_date..existing_reserva.end_date
      return false if new_reserva_range.overlaps?(existing_reserva_range)
    end
    true
  end
end
