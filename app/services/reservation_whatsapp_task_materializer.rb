class ReservationWhatsappTaskMaterializer
  Result = Struct.new(:checked, :created, :updated, keyword_init: true)

  EXCLUDED_TRIGGER_KEYS = ['reservation_confirmed'].freeze
  SERVICE_BRUNA_TRIGGER_KEY = 'service_bruna_schedule'.freeze
  SERVICE_PHOTOS_TRIGGER_KEY = 'service_printed_photos'.freeze
  SERVICE_TASK_HOUR = 9
  SERVICE_TASK_MINUTE = 0

  BRUNA_SERVICE_MATCHERS = [
    ['O passeio a cavalo', ->(name) { name.include?('passeio') && name.include?('cavalo') }],
    ['A trilha', ->(name) { name.include?('trilha') }],
    ['A massagem para duas pessoas', ->(name) { name.include?('massagem') }]
  ].freeze

  def self.run(date: Date.current)
    new(date: date).run
  end

  def initialize(date:)
    @date = date
    @result = Result.new(checked: 0, created: 0, updated: 0)
  end

  def run
    ReservationEmailTemplate.ensure_defaults!
    setting = EmailAutomationSetting.current
    return @result unless setting.enabled?

    active_templates.find_each do |template|
      reservas_scope.find_each do |reserva|
        @result.checked += 1
        materialize_task(template, reserva, setting)
      end
    end

    materialize_service_tasks

    @result
  end

  private

  def active_templates
    ReservationEmailTemplate
      .active
      .where.not(trigger_key: EXCLUDED_TRIGGER_KEYS)
  end

  def reservas_scope
    Reserva
      .active_for_operations
      .integration_ready
      .includes(:user, cabana: :filial)
  end

  def service_reservas_scope
    reservas_scope
      .where('reservas.end_date >= ?', @date)
      .includes(reserva_services: :service)
  end

  def materialize_task(template, reserva, setting)
    return unless template.matches_reserva?(reserva)

    scheduled_at = template.scheduled_at_for(reserva)
    return if scheduled_at.blank?
    return if scheduled_at.to_date > @date
    return if setting.activated_at.present? && scheduled_at < setting.activated_at

    task = ReservationWhatsappTask.find_or_initialize_by(
      reserva: reserva,
      reservation_email_template: template
    )
    return if task.completed? && task.completed_at.to_date < @date

    task.assign_attributes(
      trigger_key: template.trigger_key,
      template_name: template.display_name_for(reserva),
      message_body: template.render_whatsapp_body(reserva),
      scheduled_at: scheduled_at,
      scheduled_on: scheduled_at.to_date
    )

    return unless task.changed?

    task.new_record? ? @result.created += 1 : @result.updated += 1
    task.save!
  end

  def materialize_service_tasks
    service_reservas_scope.find_each do |reserva|
      @result.checked += 1
      materialize_bruna_service_task(reserva)
      materialize_photo_service_task(reserva)
    end
  end

  def materialize_bruna_service_task(reserva)
    return remove_service_task(reserva, SERVICE_BRUNA_TRIGGER_KEY) unless serra_reserva?(reserva)

    entries = bruna_service_entries(reserva)
    return remove_service_task(reserva, SERVICE_BRUNA_TRIGGER_KEY) if entries.empty?

    upsert_service_task(
      reserva: reserva,
      trigger_key: SERVICE_BRUNA_TRIGGER_KEY,
      template_name: 'Horários com Bruna',
      message_body: bruna_service_message(reserva, entries),
      scheduled_at: service_task_scheduled_at(reserva)
    )
  end

  def materialize_photo_service_task(reserva)
    services = photo_services(reserva)
    return remove_service_task(reserva, SERVICE_PHOTOS_TRIGGER_KEY) if services.empty?

    upsert_service_task(
      reserva: reserva,
      trigger_key: SERVICE_PHOTOS_TRIGGER_KEY,
      template_name: 'Fotos para impressão',
      message_body: photo_service_message(reserva),
      scheduled_at: service_task_scheduled_at(reserva)
    )
  end

  def upsert_service_task(reserva:, trigger_key:, template_name:, message_body:, scheduled_at:)
    return remove_service_task(reserva, trigger_key) if scheduled_at.blank?

    scope = ReservationWhatsappTask.where(reserva: reserva, trigger_key: trigger_key)
    task = scope.order(:id).first || ReservationWhatsappTask.new(reserva: reserva, trigger_key: trigger_key)

    scope.where.not(id: task.id).destroy_all if task.persisted?

    content_changed = task.persisted? && (
      task.message_body != message_body ||
      task.scheduled_at != scheduled_at ||
      task.scheduled_on != scheduled_at.to_date
    )

    task.assign_attributes(
      reservation_email_template: nil,
      trigger_key: trigger_key,
      template_name: template_name,
      message_body: message_body,
      scheduled_at: scheduled_at,
      scheduled_on: scheduled_at.to_date
    )

    if content_changed
      task.completed_at = nil
      task.morning_notified_on = nil
      task.evening_notified_on = nil
    end

    return unless task.changed?

    task.new_record? ? @result.created += 1 : @result.updated += 1
    task.save!
  end

  def remove_service_task(reserva, trigger_key)
    tasks = ReservationWhatsappTask.where(reserva: reserva, trigger_key: trigger_key)
    @result.updated += tasks.size if tasks.exists?
    tasks.destroy_all
  end

  def bruna_service_entries(reserva)
    active_service_items(reserva).filter_map do |reserva_service|
      normalized_name = normalize(reserva_service.service&.name)
      label, = BRUNA_SERVICE_MATCHERS.find { |_, matcher| matcher.call(normalized_name) }
      next if label.blank?

      [reserva_service, label]
    end
  end

  def photo_services(reserva)
    active_service_items(reserva).select do |reserva_service|
      service = reserva_service.service
      service&.photo_print_service? || normalize(service&.name).match?(/foto.*impress/)
    end
  end

  def active_service_items(reserva)
    items =
      if reserva.association(:reserva_services).loaded?
        reserva.reserva_services
      else
        reserva.reserva_services.includes(:service)
      end

    items.select(&:active?)
  end

  def bruna_service_message(reserva, entries)
    lines = entries.sort_by { |reserva_service, label| [reserva_service.service_date || reserva.start_date, label] }.map do |reserva_service, label|
      service_date = reserva_service.service_date || reserva.start_date
      "#{label} dia #{format_short_date(service_date)} na #{cabana_name(reserva)}, código de reserva ##{reserva.id}, será qual horário?"
    end

    "Oi Bruna, tudo bem?\n\n#{lines.join("\n")}"
  end

  def photo_service_message(reserva)
    "Oi #{reserva.guest_name.presence || reserva.user&.name}, como vai?\n\n" \
      "Precisamos que envie 3 fotos para impressão. Caso fique muito próximo da data, talvez não consigamos entregar as fotos a tempo.\n\n" \
      "Consegue enviar ainda hoje?"
  end

  def service_task_scheduled_at(reserva)
    return if reserva.start_date.blank?

    scheduled_date = reserva.start_date - 5.days
    Time.zone.local(scheduled_date.year, scheduled_date.month, scheduled_date.day, SERVICE_TASK_HOUR, SERVICE_TASK_MINUTE)
  end

  def serra_reserva?(reserva)
    normalized_filial = normalize(reserva.cabana&.filial&.name)

    normalized_filial.include?('serra') || normalized_filial.include?('mantiqueira')
  end

  def cabana_name(reserva)
    reserva.cabana&.guest_display_name.presence || reserva.cabana&.name.to_s
  end

  def format_short_date(date)
    return '-' if date.blank?

    date.strftime('%d/%m')
  end

  def normalize(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, ' ')
        .squish
  end
end
