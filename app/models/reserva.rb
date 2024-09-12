class Reserva < ApplicationRecord
  belongs_to :cabana
  belongs_to :user
  has_many :reserva_services, dependent: :destroy
  has_many :services, through: :reserva_services

  validate :start_date_cannot_be_in_the_past
  validate :end_date_after_start_date
  validate :dates_available

  def calculate_total_price
    total_price = 0
    days_stayed = (start_date...end_date).count

    # Calculate price for each day based on the cabana's price rules
    (start_date...end_date).each do |date|
      total_price += find_price_for_day(date)
    end

    # Calculate the total price of selected services (e.g., breakfast)
    reserva_services.each do |reserva_service|
      service = reserva_service.service
      total_price += reserva_service.quantity * service.price * days_stayed
    end

    total_price
  end


  private

  def find_price_for_day(date)
    if Holiday.holiday?(date)
      price_rule = cabana.price_rules.find_by(day_type: 'holiday')
    elsif weekend?(date)
      price_rule = cabana.price_rules.find_by(day_type: 'weekend')
    else
      price_rule = cabana.price_rules.find_by(day_type: 'weekday')
    end

    price_rule ? price_rule.price : cabana.price || 0
  end

  def weekend?(date)
    date.friday? || date.saturday? || date.sunday?
  end

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
