class ReservationWhatsappTaskMaterializer
  Result = Struct.new(:checked, :created, :updated, keyword_init: true)

  EXCLUDED_TRIGGER_KEYS = ['reservation_confirmed'].freeze
  SERVICE_BRUNA_TRIGGER_KEY = 'service_bruna_schedule'.freeze
  SERVICE_PHOTOS_LEGACY_TRIGGER_KEY = 'service_printed_photos'.freeze
  SERVICE_PHOTOS_GUEST_TRIGGER_KEY = 'service_printed_photos_guest_missing'.freeze
  SERVICE_PHOTOS_CONCIERGE_PENDING_TRIGGER_KEY = 'service_printed_photos_concierge_missing'.freeze
  SERVICE_PHOTOS_CARTOON_TRIGGER_KEY = 'service_printed_photos_cartoon'.freeze
  SERVICE_PHOTOS_CONCIERGE_PICKUP_TRIGGER_KEY = 'service_printed_photos_concierge_pickup'.freeze
  SERVICE_PHOTOS_BRUNA_TRIGGER_KEY = 'service_printed_photos_bruna'.freeze
  SERVICE_PHOTOS_TRIGGER_KEYS = [
    SERVICE_PHOTOS_LEGACY_TRIGGER_KEY,
    SERVICE_PHOTOS_GUEST_TRIGGER_KEY,
    SERVICE_PHOTOS_CONCIERGE_PENDING_TRIGGER_KEY,
    SERVICE_PHOTOS_CARTOON_TRIGGER_KEY,
    SERVICE_PHOTOS_CONCIERGE_PICKUP_TRIGGER_KEY,
    SERVICE_PHOTOS_BRUNA_TRIGGER_KEY
  ].freeze
  SERVICE_TASK_HOUR = 9
  SERVICE_TASK_MINUTE = 0
  PAPELARIA_CARTOON_NAME = 'Papelaria Cartoon'.freeze
  PAPELARIA_CARTOON_PHONE = '+55 18 99163-6225'.freeze
  CONCIERGE_NAME = 'Concierge'.freeze
  CONCIERGE_PHONE = '+55 35 91003-3417'.freeze

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
    materialize_recurring_maintenance_tasks

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

  def materialize_recurring_maintenance_tasks
    return unless defined?(RecurringMaintenanceSync)
    return unless defined?(RecurringMaintenanceWhatsappTaskSync)

    FakeHolmyCleaningSync.run(start_date: @date) if defined?(FakeHolmyCleaningSync)
    RecurringMaintenanceSync.run(start_date: @date)
    maintenance_result = RecurringMaintenanceWhatsappTaskSync.run(date: @date)
    @result.checked += maintenance_result.checked_occurrences.to_i
    @result.created += maintenance_result.created.to_i
    @result.updated += maintenance_result.updated.to_i + maintenance_result.removed.to_i
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
    return remove_service_tasks(reserva, SERVICE_PHOTOS_TRIGGER_KEYS) if services.empty?

    scheduled_at = service_task_scheduled_at(reserva)
    return remove_service_tasks(reserva, SERVICE_PHOTOS_TRIGGER_KEYS) if scheduled_at.blank?

    pdf_service = services.detect { |reserva_service| reserva_service.photo_print_pdf.attached? }

    if pdf_service.present?
      materialize_photo_pdf_tasks(reserva, pdf_service, scheduled_at)
    else
      materialize_photo_missing_tasks(reserva, services.first, scheduled_at)
    end
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

  def upsert_service_recipient_task(reserva:, trigger_key:, template_name:, message_body:, scheduled_at:, recipient_name:, recipient_phone:)
    return remove_service_task(reserva, trigger_key) if scheduled_at.blank?

    scope = ReservationWhatsappTask.where(reserva: reserva, trigger_key: trigger_key)
    signature = recipient_signature(recipient_name, recipient_phone)
    existing_tasks = scope.to_a
    task = existing_tasks.find do |candidate|
      recipient_signature(candidate.recipient_name, candidate.recipient_phone) == signature
    end || ReservationWhatsappTask.new(reserva: reserva, trigger_key: trigger_key)

    existing_tasks.each do |candidate|
      next if candidate == task
      next unless recipient_signature(candidate.recipient_name, candidate.recipient_phone) == signature

      candidate.destroy
      @result.updated += 1
    end

    content_changed = task.persisted? && (
      task.template_name != template_name ||
      task.message_body != message_body ||
      task.scheduled_at != scheduled_at ||
      task.scheduled_on != scheduled_at.to_date ||
      task.recipient_name != recipient_name ||
      task.recipient_phone != recipient_phone
    )

    task.assign_attributes(
      reservation_email_template: nil,
      trigger_key: trigger_key,
      template_name: template_name,
      message_body: message_body,
      scheduled_at: scheduled_at,
      scheduled_on: scheduled_at.to_date,
      recipient_name: recipient_name,
      recipient_phone: recipient_phone
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

  def remove_service_tasks(reserva, trigger_keys)
    trigger_keys.each { |trigger_key| remove_service_task(reserva, trigger_key) }
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

  def materialize_photo_pdf_tasks(reserva, reserva_service, scheduled_at)
    remove_service_tasks(
      reserva,
      [
        SERVICE_PHOTOS_LEGACY_TRIGGER_KEY,
        SERVICE_PHOTOS_GUEST_TRIGGER_KEY,
        SERVICE_PHOTOS_CONCIERGE_PENDING_TRIGGER_KEY
      ]
    )

    if brauna_reserva?(reserva)
      remove_service_task(reserva, SERVICE_PHOTOS_BRUNA_TRIGGER_KEY)

      upsert_service_recipient_task(
        reserva: reserva,
        trigger_key: SERVICE_PHOTOS_CARTOON_TRIGGER_KEY,
        template_name: 'Fotos para impressão - papelaria',
        message_body: photo_print_shop_message(reserva, reserva_service),
        scheduled_at: scheduled_at,
        recipient_name: PAPELARIA_CARTOON_NAME,
        recipient_phone: PAPELARIA_CARTOON_PHONE
      )

      upsert_service_recipient_task(
        reserva: reserva,
        trigger_key: SERVICE_PHOTOS_CONCIERGE_PICKUP_TRIGGER_KEY,
        template_name: 'Fotos para impressão - buscar',
        message_body: photo_concierge_pickup_message(reserva, reserva_service),
        scheduled_at: scheduled_at,
        recipient_name: CONCIERGE_NAME,
        recipient_phone: CONCIERGE_PHONE
      )
    else
      remove_service_tasks(reserva, [SERVICE_PHOTOS_CARTOON_TRIGGER_KEY, SERVICE_PHOTOS_CONCIERGE_PICKUP_TRIGGER_KEY])

      upsert_service_recipient_task(
        reserva: reserva,
        trigger_key: SERVICE_PHOTOS_BRUNA_TRIGGER_KEY,
        template_name: 'Fotos para impressão - Bruna',
        message_body: photo_bruna_message(reserva, reserva_service),
        scheduled_at: scheduled_at,
        recipient_name: 'Bruna',
        recipient_phone: nil
      )
    end
  end

  def materialize_photo_missing_tasks(reserva, reserva_service, scheduled_at)
    remove_service_tasks(
      reserva,
      [
        SERVICE_PHOTOS_LEGACY_TRIGGER_KEY,
        SERVICE_PHOTOS_CARTOON_TRIGGER_KEY,
        SERVICE_PHOTOS_CONCIERGE_PICKUP_TRIGGER_KEY,
        SERVICE_PHOTOS_BRUNA_TRIGGER_KEY
      ]
    )

    upsert_service_recipient_task(
      reserva: reserva,
      trigger_key: SERVICE_PHOTOS_GUEST_TRIGGER_KEY,
      template_name: 'Fotos para impressão - hóspede',
      message_body: photo_guest_missing_message(reserva),
      scheduled_at: scheduled_at,
      recipient_name: reserva.guest_name.presence || reserva.user&.name.to_s,
      recipient_phone: reserva.guest_phone.presence || reserva.user&.telephone.to_s
    )

    upsert_service_recipient_task(
      reserva: reserva,
      trigger_key: SERVICE_PHOTOS_CONCIERGE_PENDING_TRIGGER_KEY,
      template_name: 'Fotos para impressão - acompanhar',
      message_body: photo_concierge_missing_message(reserva, reserva_service),
      scheduled_at: scheduled_at,
      recipient_name: CONCIERGE_NAME,
      recipient_phone: CONCIERGE_PHONE
    )
  end

  def bruna_service_message(reserva, entries)
    lines = entries.sort_by { |reserva_service, label| [reserva_service.service_date || reserva.start_date, label] }.map do |reserva_service, label|
      service_date = reserva_service.service_date || reserva.start_date
      "#{label} dia #{format_short_date(service_date)} na #{cabana_name(reserva)}, código de reserva ##{reserva.id}, será qual horário?"
    end

    "Oi Bruna, tudo bem?\n\n#{lines.join("\n")}"
  end

  def photo_guest_missing_message(reserva)
    "Oi #{reserva.guest_name.presence || reserva.user&.name}, como vai?\n\n" \
      "Para preparar as fotos impressas da sua estadia, precisamos que envie 3 fotos para impressão. Caso fique muito próximo da data, talvez não consigamos entregar as fotos a tempo.\n\n" \
      "Consegue enviar ainda hoje?"
  end

  def photo_print_shop_message(reserva, reserva_service)
    "Oi, tudo bem?\n\n" \
      "Segue PDF para impressão das fotos do Villaggio Girotto.\n\n" \
      "Reserva: ##{reserva.id}\n" \
      "Cabana: #{cabana_name(reserva)}\n" \
      "Estadia: #{format_short_date(reserva.start_date)} a #{format_short_date(reserva.end_date)}\n" \
      "Serviço: Fotos impressas#{service_date_text(reserva_service)}\n" \
      "PDF: #{reserva_service.photo_print_pdf_download_url}"
  end

  def photo_concierge_pickup_message(reserva, reserva_service)
    "Fotos impressas da reserva ##{reserva.id} (#{cabana_name(reserva)}) foram enviadas para a #{PAPELARIA_CARTOON_NAME}.\n\n" \
      "Buscar as fotos para a estadia de #{format_short_date(reserva.start_date)} a #{format_short_date(reserva.end_date)}.\n" \
      "PDF: #{reserva_service.photo_print_pdf_download_url}"
  end

  def photo_bruna_message(reserva, reserva_service)
    "Oi Bruna, tudo bem?\n\n" \
      "Segue PDF das fotos impressas da reserva ##{reserva.id}.\n\n" \
      "Cabana: #{cabana_name(reserva)}\n" \
      "Estadia: #{format_short_date(reserva.start_date)} a #{format_short_date(reserva.end_date)}\n" \
      "Serviço: Fotos impressas#{service_date_text(reserva_service)}\n" \
      "PDF: #{reserva_service.photo_print_pdf_download_url}"
  end

  def photo_concierge_missing_message(reserva, reserva_service)
    "A reserva ##{reserva.id} (#{cabana_name(reserva)}) comprou Fotos Impressas, mas o PDF ainda não foi enviado/gerado.\n\n" \
      "Acompanhar com o hóspede para receber as 3 fotos#{service_date_text(reserva_service)}."
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

  def brauna_reserva?(reserva)
    normalized_filial = normalize(reserva.cabana&.filial&.name)
    normalized_cabana = normalize(reserva.cabana&.name)

    normalized_filial.include?('brauna') || normalized_cabana.include?('fattoria') || normalized_cabana.include?('brauna')
  end

  def cabana_name(reserva)
    reserva.cabana&.guest_display_name.presence || reserva.cabana&.name.to_s
  end

  def service_date_text(reserva_service)
    return '' if reserva_service&.service_date.blank?

    " em #{format_short_date(reserva_service.service_date)}"
  end

  def recipient_signature(name, phone)
    normalized_phone = phone.to_s.gsub(/\D+/, '')
    return "phone:#{normalized_phone}" if normalized_phone.present?

    "name:#{normalize(name)}"
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
