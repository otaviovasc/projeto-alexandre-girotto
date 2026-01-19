class Filial < ApplicationRecord
  has_many :items, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :cabanas, dependent: :destroy

  validates :name, presence: true
  validates :region, inclusion: { in: %w[SP MG], message: 'deve ser SP ou MG' }, allow_blank: true

  REGIONS = [['São Paulo (SP)', 'SP'], ['Minas Gerais (MG)', 'MG']].freeze
end
