class Filial < ApplicationRecord
  has_many :items, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :cabanas, dependent: :destroy

  validates :name, presence: true
  validates :region, inclusion: { in: %w[SP MG], message: 'deve ser SP ou MG' }, allow_blank: true

  REGIONS = [['São Paulo (SP)', 'SP'], ['Minas Gerais (MG)', 'MG']].freeze
  def pagarme_api_key_for_payments
    pagarme_api_key.presence || ENV["PAGARME_API_KEY_#{pagarme_env_suffix}"]
  end

  def pagarme_public_key_for_payments
    pagarme_encryption_key.presence || ENV["PAGARME_PUBLIC_KEY_#{pagarme_env_suffix}"]
  end

  def pagarme_account_id_for_payments
    ENV["PAGARME_ACCOUNT_ID_#{pagarme_env_suffix}"]
  end

  def cielo_checkout_merchant_id_for_payments
    ENV["CIELO_CHECKOUT_MERCHANT_ID_#{pagarme_env_suffix}"].presence ||
      default_cielo_checkout_merchant_id
  end

  def cielo_checkout_client_id_for_payments
    ENV["CIELO_CHECKOUT_CLIENT_ID_#{pagarme_env_suffix}"]
  end

  def cielo_checkout_client_secret_for_payments
    ENV["CIELO_CHECKOUT_CLIENT_SECRET_#{pagarme_env_suffix}"]
  end

  private

  def default_cielo_checkout_merchant_id
    case pagarme_env_suffix
    when 'SERRA'
      'da84afda-8edf-4d2b-9089-4ba1dd47a5ba'
    when 'BRAUNA'
      '48ec393d-e6cd-4734-8b68-1c307ed949ac'
    end
  end

  def pagarme_env_suffix
    normalized_name = I18n.transliterate(name.to_s).upcase
    return 'BRAUNA' if normalized_name.include?('BRAUNA')
    return 'SERRA' if normalized_name.include?('SERRA')

    normalized_name.gsub(/[^A-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
  end
end
