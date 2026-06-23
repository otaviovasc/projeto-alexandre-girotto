module Fnrh
  class Configuration
    class << self
      def enabled?
        ActiveModel::Type::Boolean.new.cast(
          ENV.fetch('FNRH_ENABLED', Rails.env.development? ? 'true' : 'false')
        )
      end

      def mode
        ENV.fetch('FNRH_MODE', Rails.env.production? ? 'real' : 'mock')
      end

      def mock?
        mode == 'mock'
      end

      def base_url
        ENV.fetch('FNRH_BASE_URL') do
          homologation? ? homologation_base_url : production_base_url
        end.delete_suffix('/')
      end

      def username_for(filial)
        ENV["FNRH_USERNAME_#{credential_suffix(filial)}"].presence || ENV['FNRH_USERNAME']
      end

      def password_for(filial)
        ENV["FNRH_PASSWORD_#{credential_suffix(filial)}"].presence || ENV['FNRH_PASSWORD']
      end

      def checkout_time
        ENV.fetch('FNRH_DEFAULT_CHECKOUT_TIME', '12:00')
      end

      def homologation?
        ENV.fetch('FNRH_ENV', Rails.env.production? ? 'production' : 'homologation') == 'homologation'
      end

      def credential_suffix(filial)
        normalized_name = I18n.transliterate(filial&.name.to_s).upcase
        return 'BRAUNA' if normalized_name.include?('BRAUNA')
        return 'SERRA' if normalized_name.include?('SERRA')

        normalized_name.gsub(/[^A-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '').presence || 'DEFAULT'
      end

      private

      def production_base_url
        'https://fnrh.turismo.serpro.gov.br/FNRH_API/rest/v2'
      end

      def homologation_base_url
        'https://hom-lowcode.serpro.gov.br/FNRH_API/rest/v2'
      end
    end
  end
end
