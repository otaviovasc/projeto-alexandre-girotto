class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :item, optional: true
  belongs_to :service, optional: true

  validate :item_or_service_present

  private

  def item_or_service_present
    if item_id.nil? && service_id.nil?
      errors.add(:base, "Necessario adicionar pelo menos 1 item ou serviço")
    end
  end
end
