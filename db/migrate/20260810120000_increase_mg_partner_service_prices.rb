class IncreaseMgPartnerServicePrices < ActiveRecord::Migration[7.0]
  class MigrationFilial < ActiveRecord::Base
    self.table_name = "filials"
  end

  class MigrationService < ActiveRecord::Base
    self.table_name = "services"
  end

  MULTIPLIER = BigDecimal("1.05")

  def up
    update_mg_partner_prices { |price| (price * MULTIPLIER).round(2) }
  end

  def down
    update_mg_partner_prices { |price| (price / MULTIPLIER).round(2) }
  end

  private

  def update_mg_partner_prices
    filial = MigrationFilial.all.detect do |record|
      normalize(record.name).include?("serra da mantiqueira")
    end
    raise "Filial Serra da Mantiqueira não encontrada" unless filial

    MigrationService.where(filial_id: filial.id).find_each do |service|
      next unless partnership_service?(service)

      current_price = BigDecimal(service.partner_price.to_s)
      service.update_columns(partner_price: yield(current_price))
    end
  end

  def partnership_service?(service)
    name = normalize(service.name)

    return true if name.include?("trilha")
    return true if name.include?("passeio") && name.include?("cavalo")
    return true if name.include?("massagem")
    return true if name.include?("espumante")
    return true if name.include?("foto") && name.include?("impress")
    return true if name.include?("petala") && name.include?("luzinha")
    return true if name.include?("cafe") && name.include?("manha")
    return true if name.include?("almoco")
    return true if name.include?("jantar")
    return true if name.include?("piquenique")
    return true if name.include?("tabua") && name.include?("frio")
    return true if name.include?("fondue")

    false
  end

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.squish
  end
end
