class ReservaService < ApplicationRecord
  attr_accessor :skip_breakfast_override

  belongs_to :reserva
  belongs_to :service

  has_many_attached :photo_print_images
  has_one_attached :photo_print_pdf

  enum status: {
    active: 'active',
    cancelled: 'cancelled',
    pending_portal: 'pending_portal',
    pending_payment: 'pending_payment'
  }

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :service_date, presence: true
  validate :service_date_within_official_stay, on: :create

  before_save :mark_manual_date_override, if: :cleaning_service?
  before_save :mark_breakfast_manual_override_on_cancellation, if: :included_breakfast_service?
  before_destroy :mark_breakfast_manual_override_on_destroy, if: :included_breakfast_service?
  after_save :ensure_cleaning_pair, if: :cleaning_service?

  scope :active_services, -> { where(status: 'active') }
  scope :cancelled_services, -> { where(status: 'cancelled') }

  def cancel!
    update!(status: 'cancelled')
  end

  def self.free_date_service?(service)
    normalized_name = I18n.transliterate(service&.name.to_s)
                          .downcase
                          .gsub(/[^a-z0-9]+/, ' ')
                          .squish

    normalized_name.split.any? { |word| word.start_with?('cobr') }
  end

  def guest_change_allowed?(date = Date.current)
    active? &&
      !automatic_included_breakfast? &&
      reserva&.service_purchase_window_open?(date) &&
      (!purchased_after_service_deadline? || reserva&.service_purchase_override_open?(date))
  end

  def guest_change_block_reason(date = Date.current)
    return 'Serviço cancelado.' if cancelled?
    return 'Este serviço foi incluído automaticamente e não pode ser alterado pelo hóspede.' if automatic_included_breakfast?
    return 'O prazo para alterar serviços pelo sistema já encerrou.' unless reserva&.service_purchase_window_open?(date)
    return 'Este serviço foi comprado com liberação especial fora do prazo normal. Alterações devem ser feitas pelo atendimento.' if purchased_after_service_deadline? && !reserva&.service_purchase_override_open?(date)

    nil
  end

  def photo_print_pdf_download_url
    return unless photo_print_pdf.attached?

    host = ENV['APP_HOST'].presence || ENV['RENDER_EXTERNAL_HOSTNAME'].presence || 'villaggio-stock.onrender.com'
    host = host.sub(%r{\Ahttps?://}, '')

    Rails.application.routes.url_helpers.photo_print_pdf_admin_reserva_service_url(
      self,
      host: host,
      protocol: 'https'
    )
  end

  private

  def cleaning_service?
    CleaningServicesAssigner.cleaning_service?(service)
  end

  def included_breakfast_service?
    BreakfastServicesAssigner.included_breakfast_service?(self)
  end

  def automatic_included_breakfast?
    BreakfastServicesAssigner.included_breakfast_service?(self)
  end

  def service_date_within_official_stay
    return if cleaning_service?
    return if self.class.free_date_service?(service)
    return if reserva.blank? || reserva.start_date.blank? || reserva.end_date.blank? || service_date.blank?
    return if service_date.between?(reserva.start_date, reserva.end_date)

    errors.add(:service_date, 'deve estar entre o check-in e o check-out da reserva.')
  end

  def mark_manual_date_override
    return unless respond_to?(:manual_date_override=)

    expected_date = CleaningServicesAssigner.expected_date_for(reserva, service)
    self.manual_date_override = expected_date.present? &&
                                service_date.present? &&
                                service_date != expected_date
  end

  def ensure_cleaning_pair
    CleaningServicesAssigner.new(reserva).call
  end

  def mark_breakfast_manual_override_on_cancellation
    return unless persisted?
    return unless will_save_change_to_status? && status == 'cancelled'

    mark_reserva_breakfast_manual_override
  end

  def mark_breakfast_manual_override_on_destroy
    return if skip_breakfast_override

    mark_reserva_breakfast_manual_override
  end

  def mark_reserva_breakfast_manual_override
    reserva.breakfast_manual_override = true
    reserva.update_column(:breakfast_manual_override, true)
  end
end
