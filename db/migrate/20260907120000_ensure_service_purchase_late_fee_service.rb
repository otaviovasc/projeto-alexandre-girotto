class EnsureServicePurchaseLateFeeService < ActiveRecord::Migration[7.0]
  LATE_FEE_NAME = "Taxa administrativa para compra fora do prazo"

  def up
    Filial.find_each do |filial|
      owner = filial.users.admins.first ||
              filial.users.managers.first ||
              User.admins.first ||
              User.managers.first ||
              User.first
      next if owner.blank?

      service = filial.services.where(name: LATE_FEE_NAME).first_or_initialize
      service.assign_attributes(
        description: "Item interno usado apenas no checkout de serviços fora do prazo.",
        price: 50,
        partner_price: 50,
        region: filial.region.presence,
        show_in_marketplace: false,
        user: service.user || owner
      )
      service.save! if service.changed?
    end
  end

  def down
    Service.where(name: LATE_FEE_NAME).delete_all
  end
end
