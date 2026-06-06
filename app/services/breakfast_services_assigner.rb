class BreakfastServicesAssigner
  SERVICE_NAME = 'Café da Manhã'.freeze
  AUTO_OBSERVATION = 'Adicionado automaticamente por cafe da manha incluso na cabana'.freeze

  def initialize(reserva, source: nil, quantity: 1)
    @reserva = reserva
    @source = source.presence || reserva.origem
    @quantity = [quantity.to_i, 1].max
  end

  def add_if_configured
    return unless reserva_ready?
    return if automatic_breakfast_blocked?
    return unless @reserva.cabana.breakfast_included_for?(@source)

    upsert_breakfast_services(automatic: true)
  end

  def add_manual
    return unless reserva_ready?

    upsert_breakfast_services(automatic: false)
  end

  def sync_automatic_service_dates
    return unless reserva_ready?

    desired_dates = breakfast_dates
    current_automatic_services = automatic_breakfast_services
    return if current_automatic_services.empty?

    if partner_reservation?
      remove_automatic_services
      return
    end
    return if @reserva.breakfast_manual_override?

    current_automatic_services.each do |reserva_service|
      next if desired_dates.include?(reserva_service.service_date)

      destroy_without_manual_override(reserva_service)
    end

    upsert_breakfast_services(automatic: true)
  end

  def sync_automatic_service_date
    sync_automatic_service_dates
  end

  def self.breakfast_service?(service)
    service.present? && normalized_name(service.name) == normalized_name(SERVICE_NAME)
  end

  def self.included_breakfast_service?(reserva_service)
    breakfast_service?(reserva_service.service) &&
      reserva_service.observation.to_s == AUTO_OBSERVATION
  end

  def self.normalized_name(name)
    I18n.transliterate(name.to_s).downcase.squish
  end

  def remove_automatic_services
    automatic_breakfast_services.each { |reserva_service| destroy_without_manual_override(reserva_service) }
  end

  private

  def reserva_ready?
    @reserva.present? &&
      @reserva.cabana.present? &&
      @reserva.start_date.present? &&
      @reserva.end_date.present? &&
      @reserva.end_date > @reserva.start_date
  end

  def upsert_breakfast_services(automatic:)
    service = breakfast_service
    return unless service

    breakfast_dates.each do |service_date|
      existing = existing_breakfast_service(service_date)
      if existing
        update_existing_breakfast(existing, automatic: automatic)
      else
        @reserva.reserva_services.create!(
          service: service,
          quantity: @quantity,
          service_date: service_date,
          status: 'active',
          observation: automatic ? AUTO_OBSERVATION : nil
        )
      end
    end
  end

  def update_existing_breakfast(reserva_service, automatic:)
    return if automatic && reserva_service.observation.to_s != AUTO_OBSERVATION

    attributes = {}
    attributes[:quantity] = @quantity unless automatic
    attributes[:observation] = AUTO_OBSERVATION if automatic && reserva_service.observation.blank?

    reserva_service.update!(attributes) if attributes.any?
  end

  def existing_breakfast_service(service_date)
    @reserva.reserva_services.includes(:service).detect do |reserva_service|
      self.class.breakfast_service?(reserva_service.service) &&
        reserva_service.status != 'cancelled' &&
        reserva_service.service_date == service_date
    end
  end

  def automatic_breakfast_services
    @reserva.reserva_services.includes(:service).select do |reserva_service|
      self.class.included_breakfast_service?(reserva_service)
    end
  end

  def breakfast_service
    breakfast_services.detect { |service| service.filial_id == @reserva.cabana.filial_id } ||
      breakfast_services.detect { |service| service.region.to_s == breakfast_region } ||
      breakfast_services.first
  end

  def breakfast_services
    @breakfast_services ||= Service.all.select { |service| self.class.breakfast_service?(service) }
  end

  def breakfast_dates
    ((@reserva.start_date + 1.day)..@reserva.end_date).to_a
  end

  def breakfast_region
    @reserva.cabana&.filial&.region.presence || region_from_filial_name
  end

  def region_from_filial_name
    filial_name = I18n.transliterate(@reserva.cabana&.filial&.name.to_s).downcase
    return 'MG' if filial_name.include?('serra') || filial_name.include?('mantiqueira')
    return 'SP' if filial_name.include?('fattoria') || filial_name.include?('brauna')

    nil
  end

  def automatic_breakfast_blocked?
    @reserva.breakfast_manual_override? || partner_reservation?
  end

  def partner_reservation?
    @reserva.user&.partner?
  end

  def destroy_without_manual_override(reserva_service)
    reserva_service.skip_breakfast_override = true
    reserva_service.destroy!
  end
end
