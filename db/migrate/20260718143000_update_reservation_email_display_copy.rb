class UpdateReservationEmailDisplayCopy < ActiveRecord::Migration[7.0]
  def up
    update_template_signatures
    update_pending_delivery_signatures
  end

  def down
  end

  private

  def update_template_signatures
    return unless table_exists?(:reservation_email_templates)

    email_template_model.find_each do |record|
      fixed_body = fix_signature(record.body)
      next if fixed_body == record.body

      record.update_columns(body: fixed_body, updated_at: Time.current)
    end
  end

  def update_pending_delivery_signatures
    return unless table_exists?(:reservation_email_deliveries)

    email_delivery_model.where(status: 'pending').find_each do |record|
      fixed_body = fix_signature(record.body)
      next if fixed_body == record.body

      record.update_columns(body: fixed_body, updated_at: Time.current)
    end
  end

  def fix_signature(body)
    body.to_s.gsub("\nMaisa\nResponsável", "\nMaisa,\nResponsável")
  end

  def email_template_model
    @email_template_model ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'reservation_email_templates'
    end
  end

  def email_delivery_model
    @email_delivery_model ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'reservation_email_deliveries'
    end
  end
end
