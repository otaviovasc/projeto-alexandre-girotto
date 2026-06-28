class Reserva < ApplicationRecord
  SERVICE_PURCHASE_BLOCK_DAYS_BEFORE_CHECKIN = 10

  attr_accessor :include_breakfast, :breakfast_quantity

  belongs_to :cabana
  belongs_to :user
  belongs_to :partnership_creator,
             class_name: 'User',
             optional: true,
             inverse_of: :created_partnership_reservas

  has_many :reserva_services, dependent: :destroy
  has_many :services, through: :reserva_services
  accepts_nested_attributes_for :reserva_services, allow_destroy: true, reject_if: proc { |attrs| attrs['service_id'].blank? }
  accepts_nested_attributes_for :user

  has_many :reserva_items, dependent: :destroy
  has_many :items, through: :reserva_items
  has_many :ical_reservation_changes, dependent: :destroy
  has_many :fnrh_events, dependent: :destroy

  validate :start_date_cannot_be_in_the_past
  validate :end_date_after_start_date
  validate :dates_available

  enum payment_status: {
    pending: 'pending',
    waiting_payment: 'waiting_payment',
    paid: 'paid',
    refused: 'refused',
    canceled: 'canceled'
  }

  before_create :set_default_fields
  before_create :set_default_payment_status
  after_create :ensure_required_cleaning_services
  after_update :shift_reservation_services_after_start_date_change, if: :saved_change_to_start_date?
  after_update :ensure_required_cleaning_services_after_schedule_change, if: :cleaning_schedule_changed?
  after_update :sync_automatic_breakfast_service_date, if: :cleaning_schedule_changed?
  after_commit :sync_fnrh_after_relevant_change, on: [:create, :update]

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

  def expired?
    payment_expires_at.present? && Time.current > payment_expires_at
  end

  def service_purchase_block_date
    return if start_date.blank?

    start_date - SERVICE_PURCHASE_BLOCK_DAYS_BEFORE_CHECKIN
  end

  def service_purchase_window_open?(date = Date.current)
    return false if service_purchase_block_date.blank?

    date < service_purchase_block_date || service_purchase_override_open?(date)
  end

  def service_purchase_override_open?(date = Date.current)
    service_purchase_override? && start_date.present? && date <= start_date
  end

  def service_purchase_closed_message
    block_date = service_purchase_block_date.strftime("%d/%m/%Y")
    check_in_date = start_date.strftime("%d/%m/%Y")

    "As compras de servicos para esta reserva ficam indisponiveis a partir de #{block_date}, #{SERVICE_PURCHASE_BLOCK_DAYS_BEFORE_CHECKIN} dias antes do check-in em #{check_in_date}."
  end

  def available?
    check_and_cancel_expired_reservations

    new_reserva_range = start_date...end_date
    overlapping_reservas = Reserva.where(cabana_id: cabana.id)
                                  .where(payment_status: [:pending, :waiting_payment, :paid])

    overlapping_reservas.each do |existing_reserva|
      existing_reserva_range = existing_reserva.start_date...existing_reserva.end_date
      return false if new_reserva_range.overlaps?(existing_reserva_range)
    end
    true
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
      update_column(:payment_status, 'canceled')
    end
  end

  def dates_available
    # Ignora validação se for reserva importada
    return if imported?

    overlapping_reservas = Reserva.where(cabana_id: cabana.id)
                                  .where(payment_status: [:pending, :waiting_payment, :paid])
    
    # Exclui a própria reserva quando está editando (não é novo registro)
    overlapping_reservas = overlapping_reservas.where.not(id: self.id) if self.persisted?

    new_reserva_range = start_date...end_date
    overlapping_reservas.each do |existing_reserva|
      existing_reserva_range = existing_reserva.start_date...existing_reserva.end_date
      if new_reserva_range.overlaps?(existing_reserva_range)
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
    group_created? && paid? && end_date.present? && end_date >= Date.current && !partnership_reservation?
  end

  def fnrh_status_label
    return 'FNRH dispensada' if partnership_reservation? && fnrh_status == 'not_eligible'

    FNRH_STATUS_LABELS.fetch(fnrh_status.to_s, fnrh_status.to_s.humanize)
  end

  def fnrh_information_released?
    partnership_reservation? || fnrh_status.in?(%w[precheckin_completed precheckin_bypassed checked_in checked_out])
  end

  def self.ransackable_attributes(auth_object = nil)
    ["breakfast_manual_override", "cabana_id", "created_at", "end_date", "group_created", "ical_date_change_since", "ical_missing_since", "ical_uid", "ical_uid_from_feed", "id", "imported_end_date", "imported_start_date", "manual_override", "partnership_creator_id", "payment_expires_at", "payment_link_id", "payment_link_url", "payment_status", "platform_uid", "service_purchase_override", "start_date", "total_price", "updated_at", "user_id"]
  end

  private

  def ensure_required_cleaning_services
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
    CleaningServicesAssigner.new(self, force_dates: true).call
  end

  def sync_automatic_breakfast_service_date
    BreakfastServicesAssigner.new(self).sync_automatic_service_dates
  end

  def cleaning_schedule_changed?
    saved_change_to_start_date? || saved_change_to_end_date? || saved_change_to_cabana_id?
  end

  def sync_fnrh_after_relevant_change
    relevant_fields = %w[total_price group_created payment_status start_date end_date cabana_id]
    return if (previous_changes.keys & relevant_fields).empty?
    return unless Fnrh::Configuration.enabled?

    Fnrh::ReservationSyncService.new(self).call
  end

  def set_default_fields
    self.observation ||= 'sistema'
    self.origem ||= 'sistema'
  end

  def set_default_payment_status
    self.payment_status ||= 'pending'
  end
end
