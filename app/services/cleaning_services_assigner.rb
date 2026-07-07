class CleaningServicesAssigner
  EARLY_CHECKIN_NOTE = 'Entram no próximo dia mais cedo que o padrão.'
  LATE_CHECKOUT_NOTE = 'Saem no dia anterior mais tarde que o padrão.'
  AUTOMATIC_NOTES = [EARLY_CHECKIN_NOTE, LATE_CHECKOUT_NOTE].freeze

  RULES_BY_FILIAL = {
    'serra da mantiqueira' => [
      { service_key: 'limpeza entrada mg', date_attribute: :start_date },
      { service_key: 'limpeza de saida mg', date_attribute: :end_date }
    ],
    'fattoria di brauna' => [
      { service_key: 'limpeza entrada sp', date_attribute: :start_date },
      { service_key: 'limpeza de saida sp', date_attribute: :end_date }
    ]
  }.freeze

  def self.cleaning_service?(service)
    return false unless service

    cleaning_service_keys.include?(service_key(service.name))
  end

  def self.expected_date_for(reserva, service)
    rule = rule_for_service(service)
    return unless rule

    case rule[:date_attribute]
    when :start_date
      reserva.early_checkin? ? reserva.start_date - 1.day : reserva.start_date
    when :end_date
      reserva.late_checkout? ? reserva.end_date + 1.day : reserva.end_date
    end
  end

  def self.rule_for_service(service)
    return unless service

    RULES_BY_FILIAL.values.flatten.find do |rule|
      rule[:service_key] == service_key(service.name)
    end
  end

  def self.cleaning_service_keys
    RULES_BY_FILIAL.values.flatten.map { |rule| rule[:service_key] }
  end

  def self.service_key(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, ' ')
        .squish
  end

  def initialize(reserva, force_dates: false)
    @reserva = reserva
    @force_dates = force_dates
  end

  def call
    remove_cleaning_services_from_other_regions

    rules.each do |rule|
      service = service_matching(rule[:service_key])
      next unless service

      reserva_service = ReservaService.find_or_initialize_by(reserva: @reserva, service: service)
      reserva_service.quantity ||= 1
      assign_date(reserva_service, self.class.expected_date_for(@reserva, service))
      assign_observation(reserva_service, automatic_note_for(rule))
      reserva_service.save! if reserva_service.new_record? || reserva_service.changed?
    end
  end

  private

  def remove_cleaning_services_from_other_regions
    desired_service_keys = rules.map { |rule| rule[:service_key] }
    return if desired_service_keys.empty?

    @reserva.reserva_services.includes(:service).each do |reserva_service|
      next unless self.class.cleaning_service?(reserva_service.service)
      next if desired_service_keys.include?(self.class.service_key(reserva_service.service.name))

      reserva_service.destroy!
    end
  end

  def assign_date(reserva_service, expected_date)
    manual_override = reserva_service.respond_to?(:manual_date_override?) &&
                      reserva_service.manual_date_override?
    return if reserva_service.persisted? && manual_override && !@force_dates

    reserva_service.service_date = expected_date
    reserva_service.manual_date_override = false if reserva_service.respond_to?(:manual_date_override=)
  end

  def assign_observation(reserva_service, automatic_note)
    manual_lines = reserva_service.observation.to_s.lines.map(&:strip).reject do |line|
      line.blank? || AUTOMATIC_NOTES.include?(line)
    end
    manual_lines << automatic_note if automatic_note.present?
    reserva_service.observation = manual_lines.join("\n").presence
  end

  def automatic_note_for(rule)
    return EARLY_CHECKIN_NOTE if rule[:date_attribute] == :start_date && @reserva.early_checkin?
    return LATE_CHECKOUT_NOTE if rule[:date_attribute] == :end_date && @reserva.late_checkout?
  end

  def rules
    RULES_BY_FILIAL[self.class.service_key(@reserva.cabana&.filial&.name)] || []
  end

  def service_matching(service_key)
    service_matching_in_scope(service_key, Service.where(filial_id: @reserva.cabana&.filial_id)) ||
      service_matching_in_scope(service_key, Service.all)
  end

  def service_matching_in_scope(service_key, scope)
    scope.detect { |service| self.class.service_key(service.name) == service_key }
  end
end
