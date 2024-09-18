class ReservaItem < ApplicationRecord
  belongs_to :reserva
  belongs_to :item
end
