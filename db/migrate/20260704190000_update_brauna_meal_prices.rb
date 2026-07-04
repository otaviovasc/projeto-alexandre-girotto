class UpdateBraunaMealPrices < ActiveRecord::Migration[7.0]
  class MigrationFilial < ActiveRecord::Base
    self.table_name = "filials"
  end

  class MigrationService < ActiveRecord::Base
    self.table_name = "services"
  end

  NEW_PRICES = {
    "cafe da manha" => { price: 129, partner_price: 98 },
    "piquenique" => { price: 116, partner_price: 98 },
    "almoco" => { price: 109, partner_price: 95 },
    "jantar" => { price: 109, partner_price: 95 },
    "(1) espumante" => { price: 52, partner_price: 52 }
  }.freeze

  PREVIOUS_PRICES = {
    "cafe da manha" => { price: 112, partner_price: 65 },
    "piquenique" => { price: 111, partner_price: 65 },
    "almoco" => { price: 91, partner_price: 65 },
    "jantar" => { price: 91, partner_price: 65 },
    "(1) espumante" => { price: 52, partner_price: 35 }
  }.freeze

  def up
    update_prices(NEW_PRICES)
  end

  def down
    update_prices(PREVIOUS_PRICES)
  end

  private

  def update_prices(prices)
    filial = MigrationFilial.all.detect do |record|
      normalize(record.name).include?("fattoria di brauna")
    end
    raise "Filial Fattoria di Brauna não encontrada" unless filial

    services = MigrationService.where(filial_id: filial.id).to_a
    prices.each do |service_name, values|
      service = services.detect { |record| normalize(record.name) == service_name }
      raise "Serviço #{service_name} não encontrado em Fattoria di Brauna" unless service

      service.update_columns(values)
    end
  end

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.squish
  end
end
