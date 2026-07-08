module PortalReservaHelper
  MG_MENUS = {
    "almoco" => {
      0 => "Carne de porco, arroz, feijão, batata frita e salada",
      1 => "Carne de frango, arroz, feijão e salada",
      2 => "Truta, arroz, salada e pão",
      3 => "Carne de porco, arroz, feijão, batata frita e salada",
      4 => "Truta, arroz, salada e pão",
      5 => "Carne de frango, arroz, feijão e salada",
      6 => "Truta, arroz, salada e pão"
    },
    "jantar" => {
      0 => "Lasanha de queijo, arroz e salada",
      1 => "Macarrão ao sugo",
      2 => "Macarrão à bolonhesa",
      3 => "Lasanha de queijo, arroz e salada",
      4 => "Macarrão com molho branco",
      5 => "Macarrão à bolonhesa, queijo ralado e pão",
      6 => "Macarrão com molho branco"
    }
  }.freeze

  WEEKDAYS = %w[Domingo Segunda-feira Terça-feira Quarta-feira Quinta-feira Sexta-feira Sábado].freeze

  def ordered_portal_service_groups(services)
    grouped_services = services.group_by(&:portal_category)

    Service::PORTAL_CATEGORY_ORDER.filter_map do |category|
      [category, grouped_services[category]] if grouped_services[category].present?
    end
  end

  def portal_service_menu(service, reserva)
    return unless service.portal_region == "MG"

    normalized_name = service.name.to_s.parameterize
    menu = MG_MENUS["almoco"] if normalized_name.include?("almoco")
    menu ||= MG_MENUS["jantar"] if normalized_name.include?("jantar")
    return unless menu

    (reserva.start_date..reserva.end_date).map do |date|
      ["#{WEEKDAYS[date.wday]}, #{date.strftime('%d/%m')}", menu.fetch(date.wday)]
    end
  end

  def printed_photos_service?(service)
    service.name.to_s.parameterize.match?(/foto.*impress/)
  end
end
