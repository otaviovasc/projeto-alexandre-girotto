class UpdateServicePortalDescriptions < ActiveRecord::Migration[7.0]
  class MigrationFilial < ActiveRecord::Base
    self.table_name = "filials"
  end

  class MigrationService < ActiveRecord::Base
    self.table_name = "services"
  end

  def up
    filials = MigrationFilial.all.index_by(&:id)

    MigrationService.find_each do |service|
      description = description_for(service, filials[service.filial_id])
      next if description == :unchanged

      service.update_columns(description: description)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def description_for(service, filial)
    name = normalize(service.name)
    region = region_for(service, filial)

    return lunch_or_dinner_description(region) if name.include?("almoco") || name.include?("jantar")
    return breakfast_description(region) if name.include?("cafe") && name.include?("manha")
    return picnic_description(region) if name.include?("piquenique")
    return "Seleção de frios e acompanhamentos." if name.include?("tabua") && name.include?("frio")
    return "Escolha entre fondue de queijo com pães caseiros ou fondue de chocolate com frutas locais." if name.include?("fondue")
    return trail_description(region) if name.include?("trilha")
    return "Passeio acompanhado por guia, com duração de até 1 hora." if name.include?("cavalo")
    return "Até duas bicicletas por até 4 horas. Devolva as bicicletas trancadas após o uso." if bicycle?(name)
    return massage_description(name) if name.include?("massagem")
    return "Decoração personalizada com pétalas e luzinhas. Use a observação para explicar o pedido e quando deseja que seja preparado." if name.include?("petala") || name.include?("luzinha")
    return nil if name.include?("espumante")
    return "Até 3 fotos impressas. Envie as fotos pelo WhatsApp logo após concluir a compra." if name.include?("foto") && name.include?("impress")

    :unchanged
  end

  def lunch_or_dinner_description(region)
    return "Cardápio preparado conforme os ingredientes frescos e sazonais disponíveis na época da hospedagem." if region == "SP"

    "Refeição preparada com ingredientes locais. Consulte o cardápio de cada dia da semana."
  end

  def breakfast_description(region)
    if region == "SP"
      "Inclui 2 sanduíches de muçarela, salame e salada; 2 sanduíches de muçarela, presunto e salada; pão palito com parmesão; bolinhas de queijo; bolo; café coado e frutas variadas."
    else
      "Inclui pão, bolo do dia, suco de laranja, geleia da estação, mel, banana e mamão. Ovos, queijo local e manteiga regional podem ser pedidos separadamente."
    end
  end

  def picnic_description(region)
    description = "Seleção inspirada no café da manhã, com pães, frutas e bebidas."
    return description unless region == "SP"

    "#{description} Pode ser servido no deck, no pasto ou no local de preferência."
  end

  def trail_description(region)
    if region == "SP"
      "Passeio guiado pela região, podendo chegar até uma queda d'água. Duração de até 1 hora."
    else
      "Passeio guiado pela região, podendo passar por montanhas e quedas d'água. Duração de até 1 hora."
    end
  end

  def massage_description(name)
    people = name.match?(/duas pessoas|2 pessoas|casal/) ? "duas pessoas" : "uma pessoa"
    "Massagem relaxante para #{people}, realizada na acomodação ou em ambiente externo."
  end

  def region_for(service, filial)
    filial_name = normalize(filial&.name)
    return "SP" if filial_name.include?("brauna")
    return "MG" if filial_name.include?("serra") || filial_name.include?("mantiqueira")

    filial&.region.presence || service.region
  end

  def bicycle?(name)
    name.include?("bicicleta") || name.include?("mountainbike") || name.include?("mountain bike")
  end

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.squish
  end
end
