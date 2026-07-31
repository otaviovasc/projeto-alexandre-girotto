class PublicBookingServicesMaterializer
  AUTOMATIC_DATE_OBSERVATION = 'Data do serviço definida automaticamente pelo sistema. O hóspede pode ajustar no menu de serviços dentro do prazo.'

  def self.call(reserva_payment)
    new(reserva_payment).call
  end

  def initialize(reserva_payment)
    @reserva_payment = reserva_payment
    @reserva = reserva_payment.reserva
    @sequence_positions = Hash.new(0)
    @allocated_dates = Hash.new { |hash, key| hash[key] = [] }
  end

  def call
    return [] unless @reserva_payment.public_booking?
    return [] if @reserva_payment.public_booking_services.blank?
    return existing_services.to_a if existing_services.exists?

    created_services = []

    ReservaService.transaction do
      service_items.each do |entry|
        dates_for_service(entry).tally.each do |service_date, quantity|
          service = entry[:service]
          unit_price = entry[:unit_price]
          observation = service_observation(entry)

          created_services << @reserva.reserva_services.create!(
            service: service,
            quantity: quantity,
            service_date: service_date,
            status: 'active',
            payment_status: 'paid',
            payment_link_id: @reserva_payment.payment_link_id,
            payment_link_url: @reserva_payment.payment_link_url,
            payment_order_code: @reserva_payment.payment_order_code,
            unit_price_paid: unit_price,
            total_paid: unit_price * quantity,
            paid_at: @reserva_payment.paid_at || Time.current,
            observation: observation.presence,
            purchased_after_service_deadline: false
          )
        end
      end
    end

    created_services
  end

  private

  def service_items
    @service_items ||= @reserva_payment.public_booking_services.filter_map do |item|
      service = Service.find_by(id: item['service_id'])
      next if service.blank?

      {
        item: item,
        service: service,
        category: service_category(service),
        quantity: positive_integer(item['quantity'], 1),
        unit_price: positive_decimal(item['unit_price'], service.price_for(@reserva) || 0),
        date_pending: ActiveModel::Type::Boolean.new.cast(item['date_pending'])
      }
    end.sort_by { |entry| category_priority(entry[:category]) }
  end

  def dates_for_service(entry)
    explicit_date = parse_service_date(entry[:item]['service_date'])
    return Array.new(entry[:quantity], explicit_date || @reserva.start_date) unless entry[:date_pending]

    candidates = automatic_date_candidates(entry[:category])
    entry[:quantity].times.map do
      index = @sequence_positions[entry[:category]]
      @sequence_positions[entry[:category]] += 1

      date = candidates[[index, candidates.length - 1].min]
      @allocated_dates[entry[:category]] << date
      date
    end
  end

  def service_observation(entry)
    observation = entry[:item]['observation'].presence
    return observation unless entry[:date_pending]

    [observation, AUTOMATIC_DATE_OBSERVATION].compact.join(' ')
  end

  def automatic_date_candidates(category)
    dates = case category
            when :checkin
              [@reserva.start_date]
            when :breakfast, :lunch
              morning_dates
            when :evening
              stay_night_dates
            when :picnic
              daytime_experience_dates
            when :board
              board_dates
            when :experience
              daytime_experience_dates
            else
              [@reserva.start_date]
            end

    dates.presence || [@reserva.start_date]
  end

  def board_dates
    return [@reserva.start_date] unless evening_service_selected? && nights_count > 1

    dates_without_evening = stay_night_dates - @allocated_dates[:evening]
    dates_without_evening.presence || stay_night_dates
  end

  def evening_service_selected?
    service_items.any? { |entry| entry[:category] == :evening }
  end

  def morning_dates
    ((@reserva.start_date + 1)..@reserva.end_date).to_a
  end

  def stay_night_dates
    (@reserva.start_date...@reserva.end_date).to_a
  end

  def daytime_experience_dates
    return [@reserva.start_date] if nights_count <= 1

    ((@reserva.start_date + 1)...@reserva.end_date).to_a.presence || [@reserva.start_date]
  end

  def nights_count
    @nights_count ||= [(@reserva.end_date - @reserva.start_date).to_i, 1].max
  end

  def service_category(service)
    normalized_name = normalize_service_name(service.name)

    if normalized_name.match?(/decoracao|petala|luzinha|espumante|foto/)
      :checkin
    elsif normalized_name.include?('cafe da manha')
      :breakfast
    elsif normalized_name.include?('almoco')
      :lunch
    elsif normalized_name.match?(/jantar|fondue/)
      :evening
    elsif normalized_name.include?('piquenique')
      :picnic
    elsif normalized_name.include?('tabua') && normalized_name.include?('frio')
      :board
    elsif normalized_name.match?(/trilha|cavalo|bicicleta|bike|massagem/)
      :experience
    else
      :checkin
    end
  end

  def normalize_service_name(name)
    I18n.transliterate(name.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
  end

  def category_priority(category)
    {
      checkin: 0,
      breakfast: 1,
      lunch: 2,
      evening: 3,
      board: 4,
      picnic: 5,
      experience: 6
    }.fetch(category, 9)
  end

  def existing_services
    @reserva.reserva_services.where(payment_order_code: @reserva_payment.payment_order_code)
  end

  def positive_integer(value, default)
    integer = value.to_i
    integer.positive? ? integer : default
  end

  def positive_decimal(value, default)
    decimal = BigDecimal(value.to_s.tr(',', '.'))
    decimal.positive? ? decimal : default
  rescue ArgumentError, TypeError
    default
  end

  def parse_service_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
