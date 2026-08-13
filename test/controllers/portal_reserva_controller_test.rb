require "test_helper"

class PortalReservaControllerTest < ActionDispatch::IntegrationTest
  test "allows access to the portal menu after the service purchase deadline" do
    reserva = reservas(:one)
    reserva.update_columns(fnrh_status: "precheckin_bypassed")

    post portal_reserva_acessar_path, params: {
      reserva_id: reserva.id,
      identificador: reserva.user.name.split.first
    }

    assert_redirected_to portal_reserva_inicio_path

    get portal_reserva_servicos_path

    assert_redirected_to portal_reserva_inicio_path
    assert_match "10 dias antes do check-in", flash[:alert]
  end

  test "blocks guest services before FNRH information is released" do
    reserva = reservas(:one)
    reserva.update_columns(fnrh_status: "awaiting_precheckin")

    post portal_reserva_acessar_path, params: {
      reserva_id: reserva.id,
      identificador: reserva.user.name.split.first
    }

    assert_redirected_to portal_reserva_inicio_path

    get portal_reserva_inicio_path

    assert_redirected_to fnrh_terms_path
    assert_equal "Conclua o pré-check-in para acessar os serviços e o material do hóspede.", flash[:alert]
  end

  test "accepts observations for decorations and surprises" do
    controller = PortalReservaController.new

    assert controller.send(:decoration_service_for_observation?, Service.new(name: "Decoração de Pétalas e Luzinhas"))
    assert controller.send(:decoration_service_for_observation?, Service.new(name: "Espumante"))
    assert controller.send(:decoration_service_for_observation?, Service.new(name: "Fotos Impressas (até 3)"))
    assert_not controller.send(:decoration_service_for_observation?, Service.new(name: "Passeio a Cavalo"))
  end

  test "requires and includes the fondue choice in the observation" do
    controller = PortalReservaController.new
    service = Service.new(name: "Kit de Fondue")
    controller.params = ActionController::Parameters.new(
      fondue_choice: "chocolate",
      observation: "Sem lactose"
    )

    assert controller.send(:fondue_service?, service)
    assert controller.send(:food_service_for_observation?, service)
    assert_equal "Fondue: chocolate. Sem lactose", controller.send(:observation_for_service, service)
  end

  test "does not add blank fondue choice while editing existing observation" do
    controller = PortalReservaController.new
    service = Service.new(name: "Kit de Fondue")

    assert_equal "Fondue: chocolate. Sem lactose",
                 controller.send(
                   :observation_for_service,
                   service,
                   Date.new(2026, 8, 11),
                   manual_observation: "Fondue: chocolate. Sem lactose"
                 )
  end

  test "blocks breakfast and lunch on check in unless reservation has early check in" do
    controller = PortalReservaController.new
    reserva = Reserva.new(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 12))
    allowed_dates = [Date.new(2026, 8, 11), Date.new(2026, 8, 12)]

    ["Café da Manhã", "Almoço"].each do |service_name|
      service = Service.new(name: service_name)

      assert_equal allowed_dates, controller.send(:portal_service_dates, service, reserva), service_name
      assert_not controller.send(:portal_service_date_allowed?, service, reserva, reserva.start_date), service_name
    end

    reserva.early_checkin = true

    ["Café da Manhã", "Almoço"].each do |service_name|
      service = Service.new(name: service_name)

      assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 11), Date.new(2026, 8, 12)],
                   controller.send(:portal_service_dates, service, reserva),
                   service_name
    end
  end

  test "blocks checkout for dinner and picnic unless reservation has late checkout" do
    controller = PortalReservaController.new
    reserva = Reserva.new(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 12))
    allowed_dates = [Date.new(2026, 8, 10), Date.new(2026, 8, 11)]

    ["Jantar", "Piquenique"].each do |service_name|
      service = Service.new(name: service_name)

      assert_equal allowed_dates, controller.send(:portal_service_dates, service, reserva), service_name
      assert_not controller.send(:portal_service_date_allowed?, service, reserva, reserva.end_date), service_name
    end

    reserva.late_checkout = true

    ["Jantar", "Piquenique"].each do |service_name|
      service = Service.new(name: service_name)

      assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 11), Date.new(2026, 8, 12)],
                   controller.send(:portal_service_dates, service, reserva),
                   service_name
    end
  end

  test "always blocks checkout for cold cuts and fondue" do
    controller = PortalReservaController.new
    reserva = Reserva.new(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 12), late_checkout: true)
    allowed_dates = [Date.new(2026, 8, 10), Date.new(2026, 8, 11)]

    ["Tábua de Frios", "Kit de Fondue"].each do |service_name|
      service = Service.new(name: service_name)

      assert_equal allowed_dates, controller.send(:portal_service_dates, service, reserva), service_name
      assert_not controller.send(:portal_service_date_allowed?, service, reserva, reserva.end_date), service_name
    end
  end

  test "allows massage on every stay date without automatic timing observations" do
    controller = PortalReservaController.new
    reserva = Reserva.new(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 12))
    controller.instance_variable_set(:@reserva, reserva)
    service = Service.new(name: "Massagem para uma pessoa")

    assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 11), Date.new(2026, 8, 12)],
                 controller.send(:portal_service_dates, service, reserva)
    assert_nil controller.send(:observation_for_service, service, reserva.start_date)
    assert_nil controller.send(:observation_for_service, service, Date.new(2026, 8, 11))
    assert_nil controller.send(:observation_for_service, service, reserva.end_date)
  end

  test "keeps service date rules without adding automatic timing notes" do
    controller = PortalReservaController.new
    reserva = Reserva.new(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 12))
    controller.instance_variable_set(:@reserva, reserva)

    ["Passeio a Cavalo", "Trilha a Pé"].each do |service_name|
      service = Service.new(name: service_name)

      assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 11), Date.new(2026, 8, 12)],
                   controller.send(:portal_service_dates, service, reserva),
                   service_name
      assert_nil controller.send(:observation_for_service, service, reserva.start_date)
      assert_nil controller.send(:observation_for_service, service, Date.new(2026, 8, 11))
      assert_nil controller.send(:observation_for_service, service, reserva.end_date)
    end

    picnic = Service.new(name: "Piquenique")

    assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 11)],
                 controller.send(:portal_service_dates, picnic, reserva)
    assert_nil controller.send(:observation_for_service, picnic, reserva.start_date)
    assert_nil controller.send(:observation_for_service, picnic, Date.new(2026, 8, 11))
    assert_nil controller.send(:observation_for_service, picnic, reserva.end_date)
  end

  test "blocks trail and horse ride on checkout for Brauna even with late checkout" do
    controller = PortalReservaController.new
    filial = Filial.new(name: "Fattoria di Brauna")
    cabana = Cabana.new(name: "Zucchero - Fattoria di Brauna", filial: filial)
    reserva = Reserva.new(
      cabana: cabana,
      start_date: Date.new(2026, 8, 10),
      end_date: Date.new(2026, 8, 12),
      late_checkout: true
    )
    controller.instance_variable_set(:@reserva, reserva)
    allowed_dates = [Date.new(2026, 8, 10), Date.new(2026, 8, 11)]

    ["Passeio a Cavalo", "Trilha a Pé"].each do |service_name|
      service = Service.new(name: service_name)

      assert_equal allowed_dates,
                   controller.send(:portal_service_dates, service, reserva),
                   service_name
      assert_not controller.send(:portal_service_date_allowed?, service, reserva, reserva.end_date), service_name
      assert_nil controller.send(:observation_for_service, service, reserva.end_date), service_name
    end
  end

  test "keeps manual observation when purchased service date changes" do
    controller = PortalReservaController.new
    reserva = Reserva.new(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 12))
    controller.instance_variable_set(:@reserva, reserva)
    service = Service.new(name: "Passeio a Cavalo")

    manual_observation = controller.send(:manual_observation_without_automatic_timing, "de tarde após check-in")
    assert_nil controller.send(:observation_for_service, service, Date.new(2026, 8, 11), manual_observation: manual_observation)

    manual_observation = controller.send(:manual_observation_without_automatic_timing, "de tarde após check-in. Levar água")
    assert_equal "Levar água",
                 controller.send(:observation_for_service, service, Date.new(2026, 8, 11), manual_observation: manual_observation)
    assert_equal "Levar água",
                 controller.send(:observation_for_service, service, reserva.end_date, manual_observation: manual_observation)

    reserva.late_checkout = true
    assert_equal "Levar água",
                 controller.send(:observation_for_service, service, reserva.end_date, manual_observation: manual_observation)
  end

  test "skips automatic timing notes when early check in or late checkout gives enough stay time" do
    controller = PortalReservaController.new
    reserva = Reserva.new(
      start_date: Date.new(2026, 8, 10),
      end_date: Date.new(2026, 8, 12),
      early_checkin: true,
      late_checkout: true
    )
    controller.instance_variable_set(:@reserva, reserva)

    ["Passeio a Cavalo", "Trilha a Pé", "Piquenique", "Massagem para uma pessoa"].each do |service_name|
      service = Service.new(name: service_name)

      assert_nil controller.send(:observation_for_service, service, reserva.start_date), service_name
      assert_nil controller.send(:observation_for_service, service, reserva.end_date), service_name
    end
  end

  test "requires photos for printed photos service" do
    controller = PortalReservaController.new
    service = Service.new(name: "Fotos Impressas (até 3)")

    assert controller.send(:photo_print_service?, service)
    assert_equal "Envie as fotos para comprar Fotos Impressas.", controller.send(:photo_print_upload_error, service, [])
  end

  test "limits printed photos to three uploads" do
    controller = PortalReservaController.new
    service = Service.new(name: "Fotos Impressas")
    uploads = Array.new(4) { Struct.new(:content_type, :size).new("image/jpeg", 100) }

    assert_equal "Envie no máximo 3 fotos.", controller.send(:photo_print_upload_error, service, uploads)
  end

  test "shows guest services while hiding internal services" do
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
    evaluation_service = Service.create!(
      name: "Enviar Avaliação",
      price: 0,
      filial: regular_service.filial,
      user: regular_service.user
    )
    evaluation_item = ReservaService.create!(
      reserva: reserva,
      service: evaluation_service,
      quantity: 1,
      service_date: reserva.end_date
    )
    charge_service = Service.create!(
      name: "Cobrar",
      price: 0,
      filial: regular_service.filial,
      user: regular_service.user
    )
    charge_item = ReservaService.create!(
      reserva: reserva,
      service: charge_service,
      quantity: 1,
      service_date: reserva.end_date
    )
    reserva.update_columns(early_checkin: true, late_checkout: true)
    controller = PortalReservaController.new

    services = controller.send(:reservation_services_for_portal, reserva.reload)
    operational_services = controller.send(:operational_services_for_portal, reserva)

    assert_includes services.map(&:service), regular_service
    assert_not_includes services, cleaning_item
    assert_not_includes services, evaluation_item
    assert_not_includes services, charge_item
    assert_equal ["Early check-in", "Late checkout"], operational_services.map { |service| service[:name] }
  end
end
