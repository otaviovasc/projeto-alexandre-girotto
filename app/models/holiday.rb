class Holiday < ApplicationRecord
  validates :name, presence: true
  validates :date, presence: true

  def self.holiday?(date)
    exists?(date: date)
  end
end
