class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Reserva association
  has_many :reservas, dependent: :destroy

  # Cart association
  has_one :cart, dependent: :destroy

  # UserMailer association
  after_create :send_welcome_email

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

  # Callback para enviar o e-mail de boas-vindas após a criação do usuário

  private

  def send_welcome_email
    UserMailer.welcome_email(self, self.password).deliver_now
  end
end
