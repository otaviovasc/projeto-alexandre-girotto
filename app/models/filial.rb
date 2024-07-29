class Filial < ApplicationRecord
  has_many :items, dependent: :destroy
  has_many :users

  validates :name, presence: true
end
