class InfoDaCabana < ApplicationRecord
  belongs_to :cabana

  INFO_TYPES = %w[intro location other].freeze

  validates :info_type, inclusion: { in: INFO_TYPES }
  validates :title, :content, presence: true

  # Attach image using ActiveStorage
  has_one_attached :image
end
