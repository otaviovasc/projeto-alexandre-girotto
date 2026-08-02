class SplitCheckinDayMessagesByFilial < ActiveRecord::Migration[7.0]
  OLD_TRIGGER_KEY = 'checkin_day_7am'.freeze
  SERRA_TRIGGER_KEY = 'checkin_day_7am_serra'.freeze
  BRAUNA_TRIGGER_KEY = 'checkin_day_7am_brauna'.freeze

  def up
    return unless table_exists?(:reservation_email_templates)

    ReservationEmailTemplate.reset_column_information
    old_template = ReservationEmailTemplate.find_by(trigger_key: OLD_TRIGGER_KEY)
    active_state = old_template.nil? ? true : old_template.active?

    serra_template = seed_template(SERRA_TRIGGER_KEY, active: active_state)
    brauna_template = seed_template(BRAUNA_TRIGGER_KEY, active: active_state)

    old_template&.update_columns(active: false, updated_at: Time.current)

    migrate_pending_email_deliveries(old_template, serra_template, brauna_template)
    migrate_pending_whatsapp_tasks(old_template, serra_template, brauna_template)
  end

  def down
  end

  private

  def seed_template(trigger_key, active:)
    attributes = ReservationEmailTemplate::DEFAULTS.find { |template| template.fetch(:trigger_key) == trigger_key }
    raise ActiveRecord::IrreversibleMigration, "Modelo #{trigger_key} nao encontrado" if attributes.blank?

    template = ReservationEmailTemplate.find_or_initialize_by(trigger_key: trigger_key)
    template.assign_attributes(
      attributes.merge(
        whatsapp_body: ReservationEmailTemplate.default_whatsapp_body_for(trigger_key),
        active: active,
        system_template: true
      )
    )
    template.save!
    template
  end

  def migrate_pending_email_deliveries(old_template, serra_template, brauna_template)
    return if old_template.blank? || !table_exists?(:reservation_email_deliveries)

    ReservationEmailDelivery
      .pending
      .where(reservation_email_template_id: old_template.id)
      .includes(reserva: { cabana: :filial })
      .find_each do |delivery|
        new_template = template_for(delivery.reserva, serra_template, brauna_template)
        next if new_template.blank?

        existing = ReservationEmailDelivery.find_by(
          reserva_id: delivery.reserva_id,
          reservation_email_template_id: new_template.id
        )

        if existing.present?
          delivery.update_columns(
            status: 'skipped',
            error_message: 'Substituido por modelo de chegada por filial',
            updated_at: Time.current
          )
          next
        end

        delivery.update_columns(
          reservation_email_template_id: new_template.id,
          trigger_key: new_template.trigger_key,
          subject: new_template.render_subject(delivery.reserva),
          body: new_template.render_body(delivery.reserva),
          updated_at: Time.current
        )
      end
  end

  def migrate_pending_whatsapp_tasks(old_template, serra_template, brauna_template)
    return if old_template.blank? || !table_exists?(:reservation_whatsapp_tasks)

    ReservationWhatsappTask
      .pending
      .where(reservation_email_template_id: old_template.id)
      .includes(reserva: { cabana: :filial })
      .find_each do |task|
        new_template = template_for(task.reserva, serra_template, brauna_template)
        next if new_template.blank?

        existing = ReservationWhatsappTask.find_by(
          reserva_id: task.reserva_id,
          reservation_email_template_id: new_template.id
        )

        if existing.present?
          task.destroy!
          next
        end

        task.update_columns(
          reservation_email_template_id: new_template.id,
          trigger_key: new_template.trigger_key,
          template_name: new_template.name,
          message_body: new_template.render_whatsapp_body(task.reserva),
          updated_at: Time.current
        )
      end
  end

  def template_for(reserva, serra_template, brauna_template)
    normalized_filial_name = I18n.transliterate(reserva&.cabana&.filial&.name.to_s).downcase
    normalized_filial_name.include?('brauna') ? brauna_template : serra_template
  end
end
