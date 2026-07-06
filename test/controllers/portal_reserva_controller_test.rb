require "test_helper"

class PortalReservaControllerTest < ActionDispatch::IntegrationTest
  test "allows access to the portal menu after the service purchase deadline" do
    reserva = reservas(:one)

    post portal_reserva_acessar_path, params: {
      reserva_id: reserva.id,
      identificador: reserva.user.name.split.first
    }

    assert_redirected_to portal_reserva_inicio_path

    get portal_reserva_servicos_path

    assert_redirected_to portal_reserva_inicio_path
    assert_match "10 dias antes do check-in", flash[:alert]
  end

  test "accepts observations for decorations and surprises" do
    controller = PortalReservaController.new

    assert controller.send(:decoration_service_for_observation?, Service.new(name: "Decoração de Pétalas e Luzinhas"))
    assert controller.send(:decoration_service_for_observation?, Service.new(name: "Espumante"))
    assert controller.send(:decoration_service_for_observation?, Service.new(name: "Fotos Impressas (até 3)"))
    assert_not controller.send(:decoration_service_for_observation?, Service.new(name: "Passeio a Cavalo"))
  end

  test "shows linked services except cleaning and includes operational services" do
    reserva = reservas(:one)
    regular_service = services(:one)
    regular_service.update_column(:name, "Passeio a Cavalo")
    cleaning_service = Service.create!(
      name: "Limpeza Entrada (MG)",
      price: 0,
      filial: regular_service.filial,
      user: regular_service.user
    )
    cleaning_item = ReservaService.create!(
      reserva: reserva,
      service: cleaning_service,
      quantity: 1,
      service_date: reserva.start_date
    )
    reserva.update_columns(early_checkin: true, late_checkout: true)
    controller = PortalReservaController.new

    services = controller.send(:reservation_services_for_portal, reserva.reload)
    operational_services = controller.send(:operational_services_for_portal, reserva)

    assert_includes services.map(&:service), regular_service
    assert_not_includes services, cleaning_item
    assert_equal ["Early check-in", "Late checkout"], operational_services.map { |service| service[:name] }
  end
end
