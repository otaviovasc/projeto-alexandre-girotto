# frozen_string_literal: true

class ServicePurchaseLateFeeCart
  def self.sync!(reserva:, cart: nil)
    new(reserva: reserva, cart: cart).sync!
  end

  def self.late_fee_cart_item?(cart_item)
    late_fee_service?(cart_item&.service)
  end

  def self.late_fee_record?(record)
    late_fee_service?(record&.service)
  end

  def self.late_fee_service?(service)
    service.respond_to?(:service_purchase_late_fee?) && service.service_purchase_late_fee?
  end

  def self.late_fee_service_for(filial)
    service = filial.services.to_a.detect { |candidate| late_fee_service?(candidate) } ||
              filial.services.where(name: Service::SERVICE_PURCHASE_LATE_FEE_NAME).first_or_initialize
    owner = service.user ||
            filial.users.admins.first ||
            filial.users.managers.first ||
            User.admins.first ||
            User.managers.first ||
            User.first
    raise ActiveRecord::RecordInvalid, Service.new(filial: filial, name: Service::SERVICE_PURCHASE_LATE_FEE_NAME) if owner.blank?

    service.assign_attributes(
      name: Service::SERVICE_PURCHASE_LATE_FEE_NAME,
      description: "Item interno usado apenas no checkout de serviços fora do prazo.",
      price: Reserva::SERVICE_PURCHASE_LATE_FEE,
      partner_price: Reserva::SERVICE_PURCHASE_LATE_FEE,
      region: filial.region.presence,
      show_in_marketplace: false,
      user: owner
    )
    service.save! if service.changed? || service.new_record?
    service
  end

  def initialize(reserva:, cart: nil)
    @reserva = reserva
    @cart = cart || reserva&.user&.cart || reserva&.user&.create_cart
  end

  def sync!
    return [] if reserva.blank? || cart.blank?

    fee_items = editable_fee_items
    regular_items = editable_portal_items.reject { |cart_item| self.class.late_fee_cart_item?(cart_item) }

    if fee_required?(regular_items)
      ensure_single_fee_item!(fee_items)
    else
      fee_items.each(&:destroy!)
    end

    @editable_portal_items = nil
    editable_portal_items
  end

  private

  attr_reader :reserva, :cart

  def fee_required?(regular_items)
    regular_items.any? && reserva.service_purchase_late_fee_applicable?
  end

  def ensure_single_fee_item!(fee_items)
    fee_item = fee_items.first
    fee_items.drop(1).each(&:destroy!)

    fee_service = self.class.late_fee_service_for(reserva.cabana.filial)
    fee_item ||= editable_scope.new(
      cart: cart,
      reserva: reserva,
      service: fee_service
    )

    fee_item.assign_attributes(
      item: nil,
      service: fee_service,
      quantity: 1,
      service_date: nil,
      observation: nil,
      unit_price_paid: nil,
      total_paid: nil,
      payment_status: nil,
      payment_link_id: nil,
      payment_link_url: nil,
      payment_order_code: nil,
      payment_expires_at: nil
    )
    fee_item.service_late_fee_amount = 0 if fee_item.has_attribute?(:service_late_fee_amount)
    fee_item.purchased_after_service_deadline = true if fee_item.has_attribute?(:purchased_after_service_deadline)
    fee_item.save! if fee_item.changed? || fee_item.new_record?
  end

  def editable_fee_items
    editable_portal_items.select { |cart_item| self.class.late_fee_cart_item?(cart_item) }
  end

  def editable_portal_items
    @editable_portal_items = editable_scope.includes(:service).order(:service_date, :id).to_a
  end

  def editable_scope
    cart.cart_items
        .where(reserva: reserva, item_id: nil, payment_status: [nil, "refused"])
  end
end
