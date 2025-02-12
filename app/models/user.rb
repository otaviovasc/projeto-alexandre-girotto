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

  # Validação de unicidade do telefone
  validates :telephone, uniqueness: { case_sensitive: false, message: "já está em uso" }

  # Validação de comprimento baseado em padrões internacionais de telefone
  validates :telephone, length: { in: 8..15, message: "deve ter entre 8 e 15 dígitos" }

  # Remover caracteres não numéricos (formatação opcional)
  before_validation :sanitize_telephone

  private

  def sanitize_telephone
    self.telephone = telephone.gsub(/\D/, '') if telephone.present?
  end

  def send_welcome_email
    UserMailer.welcome_email(self, self.password).deliver_now
  end
end
