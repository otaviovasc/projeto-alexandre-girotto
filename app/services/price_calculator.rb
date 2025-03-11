# app/services/price_calculator.rb
class PriceCalculator
  def initialize(reservation)
    @reservation = reservation
    @cabana = reservation.cabana
    @date_range = reservation.start_date...reservation.end_date
    preload_data
  end

  def preload_data
    # Carrega todas as promoções que se aplicam ao intervalo da reserva.
    @promotions = @cabana.promotions.where(
      "date BETWEEN ? AND ? OR (start_date IS NOT NULL AND end_date IS NOT NULL AND start_date <= ? AND end_date >= ?)",
      @date_range.first, @date_range.last, @date_range.last, @date_range.first
    ).to_a

    @price_rules = @cabana.price_rules.group_by(&:day_type)
  end

  def total_price
    days_price = @date_range.sum { |date| price_for_day(date) }
    services_price = calculate_services_price
    days_price + services_price
  end

  def price_for_day(date)
    if (promotion = promotion_for_day(date))
      promotion.price
    else
      rule = rule_for_date(date)
      rule ? rule.price : (@cabana.price || 0)
    end
  end

  def promotion_for_day(date)
    # Verifica se há promoção de data única para o dia
    single_promo = @promotions.find { |p| p.date.present? && p.date == date }
    return single_promo if single_promo

    # Verifica promoções com intervalo (start_date e end_date preenchidos)
    interval_promo = @promotions.find do |p|
      p.start_date.present? && p.end_date.present? && (p.start_date <= date && p.end_date >= date)
    end
    interval_promo
  end

  def rule_for_date(date)
    if Holiday.holiday?(date)
      @price_rules['holiday']&.first
    elsif weekend?(date)
      @price_rules['weekend']&.first
    else
      @price_rules['weekday']&.first
    end
  end

  def weekend?(date)
    date.friday? || date.saturday? || date.sunday?
  end

  def calculate_services_price
    days_stayed = @date_range.count
    @reservation.reserva_services.sum do |reserva_service|
      service = reserva_service.service
      reserva_service.quantity * service.price * days_stayed
    end
  end
end
