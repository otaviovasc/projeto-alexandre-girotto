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
end
