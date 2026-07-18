class UpdateReservationEmailDefaultCopy < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:reservation_email_templates)

    ReservationEmailTemplate.reset_column_information

    ReservationEmailTemplate::DEFAULTS.each do |attributes|
      template = ReservationEmailTemplate.find_or_initialize_by(trigger_key: attributes.fetch(:trigger_key))
      template.assign_attributes(attributes.merge(active: template.persisted? ? template.active : true, system_template: true))
      template.save!
    end
  end

  def down
  end
end
