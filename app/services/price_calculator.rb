class PriceCalculator
  def initialize(reservation)
    @reservation = reservation
    @cabana = reservation.cabana
    @date_range = reservation.start_date...reservation.end_date
    preload_data
  end

  def preload_data
    @promotions = @cabana.promotions.where(date: @date_range).index_by(&:date)
    @price_rules = @cabana.price_rules.group_by(&:day_type)
  end

  def total_price
    days_price = @date_range.sum { |date| price_for_day(date) }
    services_price = calculate_services_price
    days_price + services_price
  end

  def price_for_day(date)
    if (promotion = @promotions[date])
      promotion.price
    else
      rule = rule_for_date(date)
      rule ? rule.price : (@cabana.price || 0)
    end
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
