class ServicePurchaseDatePolicy
  HOLIDAY_BLOCK_MESSAGE = "Para as datas selecionadas, fale diretamente com um atendente no WhatsApp para consultar a possibilidade da entrega de serviços.".freeze
  MANTIQUEIRA_SERVICE_BLOCK_DATES = (Date.new(2026, 9, 16)..Date.new(2026, 9, 19)).freeze

  def self.holiday_block_message
    HOLIDAY_BLOCK_MESSAGE
  end

  def self.blocked_service_date?(date, reserva: nil, filial: nil, cabana: nil)
    date = parse_date(date)
    return false if date.blank?
    return true if blocked_holiday_service_date?(date)

    mantiqueira_service_blocked_date?(date) &&
      mantiqueira_context?(reserva: reserva, filial: filial, cabana: cabana)
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

  def self.blocked_service_period?(start_date, end_date, reserva: nil, filial: nil, cabana: nil)
    start_date = parse_date(start_date)
    end_date = parse_date(end_date)
    return false if start_date.blank? || end_date.blank? || end_date < start_date

    (start_date..end_date).any? do |date|
      blocked_service_date?(date, reserva: reserva, filial: filial, cabana: cabana)
    end
  end

  def self.blocked_holiday_dates_in(start_date, end_date)
    start_date = parse_date(start_date)
    end_date = parse_date(end_date)
    return [] if start_date.blank? || end_date.blank? || end_date < start_date

    (start_date..end_date).select { |date| blocked_holiday_service_date?(date) }
  end

  def self.blocked_service_dates_in(start_date, end_date, reserva: nil, filial: nil, cabana: nil)
    start_date = parse_date(start_date)
    end_date = parse_date(end_date)
    return [] if start_date.blank? || end_date.blank? || end_date < start_date

    (start_date..end_date).select do |date|
      blocked_service_date?(date, reserva: reserva, filial: filial, cabana: cabana)
    end
  end

  def self.parse_date(value)
    return value.to_date if value.respond_to?(:to_date)

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def self.mantiqueira_service_blocked_date?(date)
    MANTIQUEIRA_SERVICE_BLOCK_DATES.cover?(date)
  end

  def self.mantiqueira_context?(reserva: nil, filial: nil, cabana: nil)
    candidates = [
      filial,
      cabana,
      cabana&.filial,
      reserva&.cabana,
      reserva&.cabana&.filial
    ].compact

    candidates.any? do |record|
      text = [
        record.respond_to?(:name) ? record.name : nil,
        record.respond_to?(:region) ? record.region : nil
      ].compact.join(" ")

      normalized = I18n.transliterate(text).downcase
      normalized.include?("serra") || normalized.include?("mantiqueira")
    end
  end

  private_class_method :parse_date, :mantiqueira_service_blocked_date?, :mantiqueira_context?
end
