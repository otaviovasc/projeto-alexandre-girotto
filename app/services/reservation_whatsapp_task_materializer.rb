class ReservationWhatsappTaskMaterializer
  Result = Struct.new(:checked, :created, :updated, keyword_init: true)

  EXCLUDED_TRIGGER_KEYS = ['reservation_confirmed'].freeze

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
end
