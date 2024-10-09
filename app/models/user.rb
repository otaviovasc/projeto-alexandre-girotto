class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Reserva association
  has_many :reservas

  # Cart association
  has_one :cart, dependent: :destroy

  # Assigning custom values to the roles
  enum role: { service_provider: 3, manager: 2, admin: 1, client: 0 }

  belongs_to :filial, optional: true

  # Scopes for each role
  scope :service_providers, -> { where(role: :service_provider) }
  scope :clients, -> { where(role: :client) }
  scope :managers, -> { where(role: :manager) }
  scope :admins, -> { where(role: :admin) }

  # Set default role to client
  after_initialize do
    if self.new_record?
      self.role ||= :client
    end
  end
end
