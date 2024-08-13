class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { manager: 0, admin: 1 }

  # Associations
  belongs_to :filial, optional: true

  # Scopes
  scope :manager, -> { where(role: :manager) }

  # Set default role
  after_initialize do
    if self.new_record?
      self.role ||= :manager
    end
  end
end
