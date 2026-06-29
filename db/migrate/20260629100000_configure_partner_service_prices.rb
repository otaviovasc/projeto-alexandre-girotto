class ConfigurePartnerServicePrices < ActiveRecord::Migration[7.0]
  class MigrationService < ActiveRecord::Base
    self.table_name = "services"
  end

  def up
    MigrationService.reset_column_information

    MigrationService.find_each do |service|
      partner_price = partner_price_for(service)
      next if partner_price.nil?

      service.update_columns(partner_price: partner_price)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def partner_price_for(service)
    name = normalize(service.name)

    return 98 if name.include?("trilha")
    return 98 if name.include?("passeio") && name.include?("cavalo")
    return 25 if mountain_bike_in_sp?(service, name)
    return massage_price(name) if name.include?("massagem")
    return 35 if name.include?("espumante")
    return 30 if name.include?("foto") && name.include?("impress")
    return 0 if name.include?("petala") && name.include?("luzinha")
    return 65 if name.include?("cafe") && name.include?("manha")
    return 65 if name.include?("almoco")
    return 65 if name.include?("jantar")
    return 65 if name.include?("piquenique")
    return 130 if name.include?("tabua") && name.include?("frio")
    return 100 if name.include?("fondue")

    nil
  end

  def mountain_bike_in_sp?(service, name)
    mountain_bike = name.include?("mountainbike") ||
                    name.include?("mountain bike") ||
                    (name.include?("bicicleta") && name.include?("mountain"))

    mountain_bike && service.region.to_s.upcase == "SP"
  end

  def massage_price(name)
    two_people = name.match?(/(^|\D)2(\D|$)/) ||
                 name.include?("duas pessoas") ||
                 name.include?("casal")

    two_people ? 198 : 98
  end

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.squish
  end
end
