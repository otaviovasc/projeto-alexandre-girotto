class RecurringMaintenanceRule < ApplicationRecord
  FREQUENCY_UNITS = {
    'weekly' => 'semana(s)',
    'monthly' => 'mes(es)',
    'quarterly' => 'trimestre(s)',
    'semiannual' => 'semestre(s)'
  }.freeze

  validates :title, :message_body, :recipients_text, :first_due_on, presence: true
  validates :frequency_unit, inclusion: { in: FREQUENCY_UNITS.keys }
  validates :frequency_interval,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :must_have_target_cabana
  validate :recipients_must_have_phone

  scope :active, -> { where(active: true) }

  def cabana_ids
    cabana_ids_text.to_s.scan(/\d+/).map(&:to_i).uniq
  end

  def cabana_ids=(ids)
    self.cabana_ids_text = Array(ids).reject(&:blank?).map(&:to_i).uniq.join(',')
  end

  def selected_cabanas
    scope = Cabana.includes(:filial).order(:name)
    return scope if all_cabanas?

    scope.where(id: cabana_ids)
  end

  def recipients
    recipients_text.to_s.lines.filter_map do |line|
      raw = line.strip
      next if raw.blank?

      name, phone = split_recipient(raw)
      {
        name: name.to_s.strip.presence || raw,
        phone: phone.to_s.gsub(/\D/, '').presence
      }
    end
  end

  def next_occurrence_dates(from:, through:)
    return [] if first_due_on.blank?

    current = first_due_on.to_date
    from = from.to_date
    through = through.to_date

    current = advance_date(current) while current < from

    dates = []
    while current <= through
      dates << current
      current = advance_date(current)
    end

    dates
  end

  def frequency_label
    "A cada #{frequency_interval} #{FREQUENCY_UNITS.fetch(frequency_unit)}"
  end

  private

  def split_recipient(raw)
    if raw.include?('|')
      raw.split('|', 2)
    elsif raw.include?(';')
      raw.split(';', 2)
    elsif raw.match?(/\s-\s/)
      raw.split(/\s-\s/, 2)
    else
      [raw, nil]
    end
  end

  def advance_date(date)
    case frequency_unit
    when 'weekly'
      date + frequency_interval.weeks
    when 'monthly'
      date.advance(months: frequency_interval)
    when 'quarterly'
      date.advance(months: frequency_interval * 3)
    when 'semiannual'
      date.advance(months: frequency_interval * 6)
    else
      date.advance(months: frequency_interval)
    end
  end

  def must_have_target_cabana
    return if all_cabanas?
    return if cabana_ids.any?

    errors.add(:base, 'Selecione pelo menos uma cabana ou marque todas.')
  end

  def recipients_must_have_phone
    recipients.each do |recipient|
      next if recipient[:phone].present?

      errors.add(:recipients_text, 'deve ter nome e telefone. Use uma linha por pessoa: Nome | telefone.')
      break
    end
  end
end
