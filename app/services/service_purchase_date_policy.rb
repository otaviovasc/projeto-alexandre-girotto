class ServicePurchaseDatePolicy
  HOLIDAY_BLOCK_MESSAGE = "Para as datas selecionadas, fale diretamente com um atendente no WhatsApp para consultar a possibilidade da entrega de serviços.".freeze

  def self.holiday_block_message
    HOLIDAY_BLOCK_MESSAGE
  end

  def self.blocked_holiday_service_date?(date)
    date = parse_date(date)
    return false if date.blank?

    (date.month == 12 && date.day >= 24) || (date.month == 1 && date.day <= 2)
  end

  def self.blocked_holiday_period?(start_date, end_date)
    start_date = parse_date(start_date)
    end_date = parse_date(end_date)
    return false if start_date.blank? || end_date.blank? || end_date < start_date

    (start_date..end_date).any? { |date| blocked_holiday_service_date?(date) }
  end

  def self.blocked_holiday_dates_in(start_date, end_date)
    start_date = parse_date(start_date)
    end_date = parse_date(end_date)
    return [] if start_date.blank? || end_date.blank? || end_date < start_date

    (start_date..end_date).select { |date| blocked_holiday_service_date?(date) }
  end

  def self.parse_date(value)
    return value.to_date if value.respond_to?(:to_date)

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  private_class_method :parse_date
end
