class Filial < ApplicationRecord
  has_many :items, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :users, dependent: :destroy

  validates :name, presence: true
end
