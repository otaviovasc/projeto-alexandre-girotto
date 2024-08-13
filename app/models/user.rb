class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { client: 0, manager: 1, admin: 2 }

  # Associations
  belongs_to :filial, optional: true

  # Scopes
  scope :manager, -> { where(role: :manager) }
  scope :client, -> { where(role: :client) }
  scope :admin, -> { where(role: :admin) }

  # Set default role
  after_initialize do
    if self.new_record?
      self.role ||= :client
    end
  end
end
