class Reserva < ApplicationRecord
  belongs_to :cabana
  belongs_to :user
end
