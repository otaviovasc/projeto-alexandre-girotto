class Reserva < ApplicationRecord
  attr_accessor :include_breakfast, :breakfast_quantity

  belongs_to :cabana
  belongs_to :user

  has_many :reserva_services, dependent: :destroy
  has_many :services, through: :reserva_services

  has_many :reserva_items, dependent: :destroy
  has_many :items, through: :reserva_items

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

  before_create :set_default_payment_status

  def calculate_total_price!
    self.total_price = PriceCalculator.new(self).total_price
  end

  def expired?
    payment_expires_at.present? && Time.current > payment_expires_at
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

  private

  def set_default_payment_status
    self.payment_status ||= 'pending'
  end

  def start_date_cannot_be_in_the_past
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
    unless available?
      errors.add(:base, "A Cabana esta indisponível na data selecionada.")
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    ["cabana_id", "created_at", "end_date", "id", "payment_expires_at", "payment_link_id", "payment_link_url", "payment_status", "start_date", "total_price", "updated_at", "user_id"]
  end
end
