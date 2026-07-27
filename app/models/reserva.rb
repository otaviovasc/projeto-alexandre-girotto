require 'uri'

class Reserva < ApplicationRecord
  SERVICE_PURCHASE_BLOCK_DAYS_BEFORE_CHECKIN = 10

  attr_accessor :include_breakfast, :breakfast_quantity

  belongs_to :cabana
  belongs_to :user
  belongs_to :partnership_creator,
             class_name: 'User',
             optional: true,
             inverse_of: :created_partnership_reservas
  belongs_to :canceled_by,
             class_name: 'User',
             optional: true

  has_many :reserva_services, dependent: :destroy
  has_many :services, through: :reserva_services
  accepts_nested_attributes_for :reserva_services, allow_destroy: true, reject_if: proc { |attrs| attrs['service_id'].blank? }
  accepts_nested_attributes_for :user

  has_many :reserva_items, dependent: :destroy
  has_many :items, through: :reserva_items
  has_many :reserva_payments, dependent: :destroy
  has_many :ical_reservation_changes, dependent: :destroy
  has_many :fnrh_events, dependent: :destroy
  has_many :reservation_email_deliveries, dependent: :destroy
  has_many :reservation_whatsapp_tasks, dependent: :destroy

  validate :start_date_cannot_be_in_the_past
  validate :end_date_after_start_date
  validate :dates_available
  validate :imported_operational_extensions_available
  validates :guest_name, length: { maximum: 120 }, allow_blank: true
  validates :guest_phone, length: { in: 8..15 }, allow_blank: true
  validates :guest_email,
            length: { maximum: 255 },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            allow_blank: true
  validates :service_max_installments, inclusion: { in: 1..12 }

  enum payment_status: {
    pending: 'pending',
    waiting_payment: 'waiting_payment',
    paid: 'paid',
    refused: 'refused',
    canceled: 'canceled'
  }

  scope :integration_ready, -> { where(reservas: { payment_status: 'paid', blocks_availability: true }) }
  scope :active_for_operations, -> { where.not(payment_status: 'canceled').or(where(payment_status: nil)) }
  scope :canceled_for_history, -> { where(payment_status: 'canceled') }
  scope :canceled_for_external_history, lambda {
    canceled_for_history.where.not(id: unpaid_pre_reservation_ids)
  }
  scope :unfinished_pre_reservations, lambda {
    canceled_for_history.where(id: unpaid_pre_reservation_ids)
  }

  before_create :set_default_fields
  before_create :set_default_payment_status
  before_validation :normalize_guest_details
  after_create :ensure_required_cleaning_services
  after_update :shift_reservation_services_after_start_date_change, if: :saved_change_to_start_date?
  after_update :ensure_required_cleaning_services_after_schedule_change, if: :cleaning_schedule_changed?
  after_update :sync_automatic_breakfast_service_date, if: :breakfast_schedule_changed?
  after_commit :sync_fnrh_after_relevant_change, on: [:create, :update]
  after_commit :sync_reservation_email_automations_after_relevant_change, on: [:create, :update]

  FNRH_STATUS_LABELS = {
    'not_eligible' => 'Aguardando liberação',
    'awaiting_precheckin' => 'Aguardando pré-check-in',
    'precheckin_completed' => 'Pré-check-in concluído',
    'precheckin_bypassed' => 'FNRH pulada',
    'duplicate_in_fnrh' => 'Já existe na FNRH',
    'checked_in' => 'Check-in realizado',
    'checked_out' => 'Checkout realizado',
    'cancelled' => 'Cancelada',
    'no_show' => 'No-show',
    'error' => 'Erro'
  }.freeze

  def calculate_total_price!
    self.total_price = PriceCalculator.new(self).total_price
  end

  def pending_payment_reservation_total
    (total_price || 0).to_d
  end

  def pending_payment_service_items
    reserva_services.includes(:service).select do |reserva_service|
      pending_payment_chargeable_service?(reserva_service)
    end
  end

  def pending_payment_services_total
    pending_payment_service_items.sum { |reserva_service| pending_payment_service_total(reserva_service) }
  end

  def pending_payment_checkout_total
    pending_payment_reservation_total + pending_payment_services_total
  end

  def pending_payment_service_total(reserva_service)
    unit_price = reserva_service.unit_price_paid || reserva_service.service&.price_for(self) || 0
    quantity = reserva_service.quantity.to_i.positive? ? reserva_service.quantity.to_i : 1

    unit_price.to_d * quantity
  end

  def expired?
    payment_expires_at.present? && Time.current > payment_expires_at
  end

  def service_purchase_block_date
    return if start_date.blank?

    start_date - SERVICE_PURCHASE_BLOCK_DAYS_BEFORE_CHECKIN
  end

  def service_purchase_window_open?(date = Date.current)
    return false if service_purchase_block_date.blank?

    service_purchase_regular_window_open?(date) || service_purchase_override_open?(date)
  end

  def service_purchase_regular_window_open?(date = Date.current)
    return false if service_purchase_block_date.blank?

    date < service_purchase_block_date
  end

  def service_purchase_override_open?(date = Date.current)
    service_purchase_override? && start_date.present? && date <= start_date
  end

  def service_purchase_override_used?(date = Date.current)
    !service_purchase_regular_window_open?(date) && service_purchase_override_open?(date)
  end

  def service_purchase_closed_message
    block_date = service_purchase_block_date.strftime("%d/%m/%Y")
    check_in_date = start_date.strftime("%d/%m/%Y")

    "As compras de servicos para esta reserva ficam indisponiveis a partir de #{block_date}, #{SERVICE_PURCHASE_BLOCK_DAYS_BEFORE_CHECKIN} dias antes do check-in em #{check_in_date}."
  end

  def available?
    check_and_cancel_expired_reservations

    return true unless blocks_availability?
    return false if cabana.blank? || availability_range.blank?

    overlapping_reservas = Reserva.where(cabana_id: cabana.id)
                                  .where(blocks_availability: true)
                                  .where(payment_status: [:pending, :waiting_payment, :paid])
                                  .where('payment_expires_at IS NULL OR payment_expires_at > ?', Time.current)
    overlapping_reservas = overlapping_reservas.where.not(id: id) if persisted?

    overlapping_reservas.each do |existing_reserva|
      existing_range = existing_reserva.availability_range
      return false if existing_range.present? && availability_range.overlaps?(existing_range)
    end
    true
  end

  def integration_ready?
    paid? && blocks_availability?
  end

  def unfinished_pre_reservation?
    canceled? && reserva_payments.any? && reserva_payments.none?(&:paid?)
  end

  def reserva_payment_overdue?
    if association(:reserva_payments).loaded?
      reserva_payments.any?(&:overdue?)
    else
      reserva_payments.overdue_installments.exists?
    end
  end

  def cancel_for_operations!(by:, reason: nil)
    now = Time.current

    transaction do
      reserva_services.where.not(status: 'cancelled').update_all(
        status: 'cancelled',
        updated_at: now
      )
      reserva_payments.where.not(payment_status: 'paid').update_all(
        payment_status: 'canceled',
        canceled_at: now,
        updated_at: now
      )

      update_columns(
        payment_status: 'canceled',
        blocks_availability: false,
        canceled_at: now,
        canceled_by_id: by&.id,
        cancellation_reason: reason.presence,
        ical_missing_since: nil,
        ical_date_change_since: nil,
        updated_at: now
      )
    end
  end

  def self.unpaid_pre_reservation_ids
    ReservaPayment
      .select(:reserva_id)
      .where.not(reserva_id: nil)
      .group(:reserva_id)
      .having("SUM(CASE WHEN payment_status = 'paid' THEN 1 ELSE 0 END) = 0")
  end

  def availability_start_date
    return if start_date.blank?

    early_checkin? ? start_date - 1.day : start_date
  end

  def availability_end_date
    return if end_date.blank?

    late_checkout? ? end_date + 1.day : end_date
  end

  def availability_range
    return if availability_start_date.blank? || availability_end_date.blank?

    availability_start_date...availability_end_date
  end

  def early_checkin_block_date
    start_date - 1.day if early_checkin? && start_date.present?
  end

  def late_checkout_block_date
    end_date if late_checkout? && end_date.present?
  end

  def start_date_cannot_be_in_the_past
    return if imported?

    if start_date.present? && start_date < Date.today
      errors.add(:start_date, "não pode estar no passado.")
    end
  end

  def end_date_after_start_date
    if end_date.present? && (end_date <= start_date)
      errors.add(:end_date, "deve ser após a data de início.")
    end
  end

  def check_and_cancel_expired_reservations
    if expired? && waiting_payment?
      cancel_for_operations!(by: nil, reason: 'Pagamento vencido sem confirmação.')
    end
  end

  def pending_payment_chargeable_service?(reserva_service)
    return false if reserva_service.blank? || reserva_service.cancelled?
    return false if CleaningServicesAssigner.cleaning_service?(reserva_service.service)
    return false if BreakfastServicesAssigner.included_breakfast_service?(reserva_service)
    return false if ReservaService.free_date_service?(reserva_service.service)

    true
  end

  def dates_available
    # Ignora validação se for reserva importada
    return if imported?
    return unless blocks_availability?
    return if cabana.blank? || availability_range.blank?

    overlapping_reservas = Reserva.where(cabana_id: cabana.id)
                                  .where(blocks_availability: true)
                                  .where(payment_status: [:pending, :waiting_payment, :paid])
                                  .where('payment_expires_at IS NULL OR payment_expires_at > ?', Time.current)
    
    # Exclui a própria reserva quando está editando (não é novo registro)
    overlapping_reservas = overlapping_reservas.where.not(id: self.id) if self.persisted?

    overlapping_reservas.each do |existing_reserva|
      existing_range = existing_reserva.availability_range
      if existing_range.present? && availability_range.overlaps?(existing_range)
        errors.add(:base, "A Cabana está indisponível na data selecionada.")
        break
      end
    end
  end

  def imported?
    origem.present? && origem != 'sistema'
  end

  def ical_missing?
    ical_missing_since.present?
  end

  def ical_date_changed?
    ical_date_change_since.present?
  end

  def partnership_created?
    partnership_creator_id.present?
  end

  def partnership_reservation?
    partnership_created? ||
      user&.partner? ||
      I18n.transliterate(observation.to_s).downcase.include?('parceria')
  end

  def fnrh_eligible?
    group_created? && integration_ready? && end_date.present? && end_date >= Date.current && !partnership_reservation?
  end

  def fnrh_status_label
    return 'FNRH dispensada' if partnership_reservation? && fnrh_status == 'not_eligible'

    FNRH_STATUS_LABELS.fetch(fnrh_status.to_s, fnrh_status.to_s.humanize)
  end

  def fnrh_information_released?
    partnership_reservation? || fnrh_status.in?(%w[precheckin_completed precheckin_bypassed checked_in checked_out])
  end

  def reservation_email_recipient_email
    email = guest_email.presence || user&.email
    normalized_email = email.to_s.squish.downcase
    return if normalized_email.blank? || imported_placeholder_email?(normalized_email)

    normalized_email
  end

  def reservation_confirmation_email_allowed?
    !imported?
  end

  def imported_placeholder_email?(email)
    email.to_s.downcase.end_with?('@importado.com')
  end

  def matches_reservation_identifier?(identifier)
    normalized_identifier = normalize_reservation_identifier(identifier)
    return false if normalized_identifier.blank?

    guest_candidates = [guest_name, guest_name.to_s.squish.split.first]
    guest_matches = guest_candidates.any? do |candidate|
      normalize_reservation_identifier(candidate) == normalized_identifier
    end

    guest_matches || user&.matches_reservation_identifier?(identifier)
  end

  def self.ransackable_attributes(auth_object = nil)
    ["blocks_availability", "breakfast_manual_override", "cabana_id", "canceled_at", "canceled_by_id", "cancellation_reason", "created_at", "early_checkin", "end_date", "group_created", "guest_email", "guest_name", "guest_phone", "ical_date_change_since", "ical_missing_since", "ical_uid", "ical_uid_from_feed", "id", "imported_end_date", "imported_start_date", "late_checkout", "manual_override", "partnership_creator_id", "payment_expires_at", "payment_link_id", "payment_link_url", "payment_status", "platform_uid", "service_max_installments", "service_purchase_override", "start_date", "total_price", "updated_at", "user_id"]
  end

  private

  def normalize_guest_details
    self.guest_name = guest_name.to_s.squish.presence
    self.guest_phone = guest_phone.to_s.gsub(/\D/, '').presence
    self.guest_email = guest_email.to_s.squish.downcase.presence
  end

  def normalize_reservation_identifier(value)
    I18n.transliterate(value.to_s).downcase.squish
  end

  def ensure_required_cleaning_services
    return unless integration_ready?

    CleaningServicesAssigner.new(self).call
  end

  def shift_reservation_services_after_start_date_change
    old_start_date, new_start_date = saved_change_to_start_date
    ReservationServicesDateShifter.new(
      self,
      old_start_date: old_start_date,
      new_start_date: new_start_date
    ).call
  end

  def ensure_required_cleaning_services_after_schedule_change
    return unless integration_ready?

    force_dates = saved_change_to_start_date? || saved_change_to_end_date? || saved_change_to_cabana_id?
    CleaningServicesAssigner.new(self, force_dates: force_dates).call
  end

  def sync_automatic_breakfast_service_date
    return unless integration_ready?

    BreakfastServicesAssigner.new(self).sync_automatic_service_dates
  end

  def cleaning_schedule_changed?
    saved_change_to_start_date? || saved_change_to_end_date? || saved_change_to_cabana_id? ||
      saved_change_to_early_checkin? || saved_change_to_late_checkout?
  end

  def breakfast_schedule_changed?
    saved_change_to_start_date? || saved_change_to_end_date? || saved_change_to_cabana_id?
  end

  def imported_operational_extensions_available
    return unless imported?
    return if cabana.blank? || start_date.blank? || end_date.blank?

    validate_imported_extension(:early_checkin, (start_date - 1.day)...start_date) if will_save_change_to_early_checkin? && early_checkin?
    validate_imported_extension(:late_checkout, end_date...(end_date + 1.day)) if will_save_change_to_late_checkout? && late_checkout?
  end

  def validate_imported_extension(attribute, extension_range)
    occupied = Reserva.where(cabana_id: cabana_id, payment_status: [:pending, :waiting_payment, :paid])
                       .where(blocks_availability: true)
                       .where('payment_expires_at IS NULL OR payment_expires_at > ?', Time.current)
    occupied = occupied.where.not(id: id) if persisted?
    return unless occupied.any? do |reserva|
      existing_range = reserva.availability_range
      existing_range.present? && extension_range.overlaps?(existing_range)
    end

    label = attribute == :early_checkin ? 'early check-in' : 'late checkout'
    errors.add(attribute, "não pode ser ativado porque a diária extra do #{label} já está ocupada.")
  end

  def sync_fnrh_after_relevant_change
    relevant_fields = %w[total_price group_created payment_status start_date end_date cabana_id]
    return if (previous_changes.keys & relevant_fields).empty?
    return unless Fnrh::Configuration.enabled?

    Fnrh::ReservationSyncService.new(self).call
  end

  def sync_reservation_email_automations_after_relevant_change
    relevant_fields = %w[payment_status blocks_availability start_date end_date canceled_at guest_name guest_email]
    return if (previous_changes.keys & relevant_fields).empty?

    ReservationEmailScheduler.schedule_for_reserva(self)
  rescue => e
    Rails.logger.error("Erro ao planejar e-mails da reserva ##{id}: #{e.message}")
  end

  def set_default_fields
    self.observation ||= 'Sistema'
    self.origem ||= 'sistema'
  end

  def set_default_payment_status
    self.payment_status ||= 'pending'
  end
end
