class PriceRule < ApplicationRecord
  belongs_to :cabana

  # day_type can be: 'weekday', 'weekend', 'holiday'
  validates :day_type, presence: true, inclusion: { in: ['weekday', 'weekend', 'holiday'] }
end
