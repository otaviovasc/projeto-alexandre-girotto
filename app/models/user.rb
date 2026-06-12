class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Reserva association
  has_many :reservas, dependent: :destroy
  has_many :created_partnership_reservas,
           class_name: 'Reserva',
           foreign_key: :partnership_creator_id,
           inverse_of: :partnership_creator,
           dependent: :nullify

  # Cart association
  has_one :cart, dependent: :destroy

  # UserMailer association
  after_create :send_welcome_email

  # Assigning custom values to the roles
  enum role: { service_provider: 3, manager: 2, admin: 1, client: 0, partnership_agent: 4 }

  ROLE_LABELS = {
    'service_provider' => 'Prestador de serviço',
    'manager' => 'Gerente',
    'admin' => 'Admin',
    'client' => 'Cliente',
    'partnership_agent' => 'Parcerias'
  }.freeze

  belongs_to :filial, optional: true

  # Scopes for each role
  scope :service_providers, -> { where(role: :service_provider) }
  scope :clients, -> { where(role: :client) }
  scope :managers, -> { where(role: :manager) }
  scope :admins, -> { where(role: :admin) }
  scope :partnership_agents, -> { where(role: :partnership_agent) }

  # Scopes for partner status
  scope :partners, -> { where(partner: true) }
  scope :non_partners, -> { where(partner: false) }

  def sync_filial_from_cabana!(cabana)
    return if cabana.blank? || cabana.filial_id.blank? || filial_id == cabana.filial_id

    update_column(:filial_id, cabana.filial_id)
  end

  def sync_filial_from_latest_reserva!
    return unless client?

    reserva = reservas
                .includes(cabana: :filial)
                .where(payment_status: %w[paid waiting_payment pending])
                .order(created_at: :desc)
                .first

    sync_filial_from_cabana!(reserva&.cabana)
  end

  def self.role_label(role)
    ROLE_LABELS[role.to_s] || role.to_s.humanize
  end

  def self.role_options(include_admin: true)
    keys = roles.keys
    keys = keys.reject { |role| role == 'admin' } unless include_admin

    keys.map { |role| [role_label(role), role] }
  end

  def role_label
    self.class.role_label(role)
  end

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
