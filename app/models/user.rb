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

  # Scopes for partner status
  scope :partners, -> { where(partner: true) }
  scope :non_partners, -> { where(partner: false) }

  # Set default role to client
  after_initialize do
    if self.new_record?
      self.role ||= :client
      self.partner ||= false
    end
  end

  # Validação de unicidade do telefone (só valida se não for vazio)
  validates :telephone, uniqueness: { case_sensitive: false, message: "já está em uso" }, allow_blank: true, allow_nil: true

  # Validação de comprimento baseado em padrões internacionais de telefone
  validates :telephone, length: { in: 8..15, message: "deve ter entre 8 e 15 dígitos" }, allow_blank: true

  # Validação de presença do nome
  validates :name, presence: true

  # Remover caracteres não numéricos e converter string vazia para nil
  before_validation :sanitize_telephone

  private

  def sanitize_telephone
    if telephone.present?
      self.telephone = telephone.gsub(/\D/, '')
      # Se depois da limpeza ficar vazio, definir como nil
      self.telephone = nil if self.telephone.blank?
    else
      # Converter string vazia ou espaços para nil
      self.telephone = nil
    end
  end

  def send_welcome_email
    return unless Rails.env.production? # só envia em produção
    UserMailer.with(user: self).welcome_email.deliver_later
  end
end