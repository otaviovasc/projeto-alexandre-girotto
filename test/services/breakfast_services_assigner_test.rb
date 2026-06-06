require "test_helper"

class BreakfastServicesAssignerTest < ActiveSupport::TestCase
  test "adds included breakfast for a configured direct reservation" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_direct: true
    )
    user = create_user("direct-breakfast@example.com")
    create_breakfast_service(filial)

    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "sistema").add_if_configured

    breakfasts = reserva.reserva_services.includes(:service).select do |reserva_service|
      BreakfastServicesAssigner.breakfast_service?(reserva_service.service)
    end
    breakfast_dates = breakfasts.map(&:service_date).sort

    assert_equal [Date.new(2026, 6, 13), Date.new(2026, 6, 14)], breakfast_dates
    assert breakfasts.all? { |breakfast| breakfast.quantity == 1 }
    assert breakfasts.all? { |breakfast| breakfast.observation == BreakfastServicesAssigner::AUTO_OBSERVATION }
  end

  test "adds breakfast only on checkout for a one night reservation" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_direct: true
    )
    user = create_user("one-night-breakfast@example.com")
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 8),
      end_date: Date.new(2026, 6, 9),
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "sistema").add_if_configured

    breakfast_dates = reserva.reserva_services.includes(:service).select do |reserva_service|
      BreakfastServicesAssigner.breakfast_service?(reserva_service.service)
    end.map(&:service_date)

    assert_equal [Date.new(2026, 6, 9)], breakfast_dates
  end

  test "adds breakfast on every morning after checkin through checkout" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_booking: true
    )
    user = create_user("three-breakfasts@example.com")
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 9),
      end_date: Date.new(2026, 6, 12),
      origem: "booking",
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "booking").add_if_configured

    breakfast_dates = reserva.reserva_services.includes(:service).select do |reserva_service|
      BreakfastServicesAssigner.breakfast_service?(reserva_service.service)
    end.map(&:service_date).sort

    assert_equal [Date.new(2026, 6, 10), Date.new(2026, 6, 11), Date.new(2026, 6, 12)], breakfast_dates
  end

  test "does not add included breakfast when the source is not configured" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(name: "Cabana SP", price: 100, filial: filial)
    user = create_user("no-breakfast@example.com")
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "booking").add_if_configured

    assert_empty reserva.reload.services.select { |service| BreakfastServicesAssigner.breakfast_service?(service) }
  end

  test "uses the breakfast service from the same filial" do
    filial_sp = Filial.create!(name: "Fattoria di Brauna", region: "SP")
    filial_mg = Filial.create!(name: "Serra da Mantiqueira", region: "MG")
    cabana = Cabana.create!(
      name: "Cabana MG",
      price: 100,
      filial: filial_mg,
      breakfast_included_airbnb: true
    )
    user = create_user("same-filial-breakfast@example.com")
    breakfast_sp = create_breakfast_service(filial_sp, region: "SP")
    breakfast_mg = create_breakfast_service(filial_mg, region: "MG")
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 8),
      end_date: Date.new(2026, 6, 9),
      origem: "airbnb",
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "airbnb").add_if_configured

    assert_equal breakfast_mg, breakfast_service_for(reserva).service
    assert_not_equal breakfast_sp, breakfast_service_for(reserva).service
  end

  test "uses the breakfast service from the same region when filial differs" do
    filial_cabana = Filial.create!(name: "Fattoria di Brauna", region: "SP")
    filial_servico_sp = Filial.create!(name: "Serviços SP", region: "SP")
    filial_servico_mg = Filial.create!(name: "Serviços MG", region: "MG")
    cabana = Cabana.create!(
      name: "Zucchero",
      price: 100,
      filial: filial_cabana,
      breakfast_included_booking: true
    )
    user = create_user("same-region-breakfast@example.com")
    breakfast_mg = create_breakfast_service(filial_servico_mg, region: "MG")
    breakfast_sp = create_breakfast_service(filial_servico_sp, region: "SP")
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 8),
      end_date: Date.new(2026, 6, 9),
      origem: "booking",
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "booking").add_if_configured

    assert_equal breakfast_sp, breakfast_service_for(reserva).service
    assert_not_equal breakfast_mg, breakfast_service_for(reserva).service
  end

  test "does not add included breakfast for partner reservations" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_direct: true
    )
    user = create_user("partner-breakfast@example.com")
    user.update!(partner: true)
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "sistema").add_if_configured

    assert_empty reserva.reload.services.select { |service| BreakfastServicesAssigner.breakfast_service?(service) }
  end

  test "does not recreate automatic breakfast after it is cancelled manually" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_airbnb: true
    )
    user = create_user("cancel-breakfast@example.com")
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 8),
      end_date: Date.new(2026, 6, 9),
      origem: "airbnb",
      payment_status: "paid",
      total_price: 0
    )

    assigner = BreakfastServicesAssigner.new(reserva, source: "airbnb")
    assigner.add_if_configured
    breakfast_service_for(reserva).update!(status: "cancelled")
    assigner.add_if_configured

    assert reserva.reload.breakfast_manual_override?
    assert_empty active_breakfast_services_for(reserva)
  end

  test "does not recreate automatic breakfast after it is deleted manually" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_airbnb: true
    )
    user = create_user("delete-breakfast@example.com")
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 8),
      end_date: Date.new(2026, 6, 9),
      origem: "airbnb",
      payment_status: "paid",
      total_price: 0
    )

    assigner = BreakfastServicesAssigner.new(reserva, source: "airbnb")
    assigner.add_if_configured
    breakfast_service_for(reserva).destroy!
    assigner.add_if_configured

    assert reserva.reload.breakfast_manual_override?
    assert_empty breakfast_services_for(reserva)
  end

  test "removes automatic breakfast when reservation becomes partner" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_airbnb: true
    )
    user = create_user("partner-after-breakfast@example.com")
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      origem: "airbnb",
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "airbnb").add_if_configured
    user.update!(partner: true)
    BreakfastServicesAssigner.new(reserva, source: "airbnb").sync_automatic_service_dates

    assert_empty breakfast_services_for(reserva)
  end

  test "syncs the automatic breakfast date when reservation dates change" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(
      name: "Cabana SP",
      price: 100,
      filial: filial,
      breakfast_included_airbnb: true
    )
    user = create_user("sync-breakfast@example.com")
    create_breakfast_service(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      origem: "airbnb",
      payment_status: "paid",
      total_price: 0
    )

    BreakfastServicesAssigner.new(reserva, source: "airbnb").add_if_configured
    reserva.update!(start_date: Date.new(2026, 6, 13), end_date: Date.new(2026, 6, 15))

    breakfast_dates = reserva.reserva_services.includes(:service).select do |reserva_service|
      BreakfastServicesAssigner.breakfast_service?(reserva_service.service)
    end.map(&:service_date).sort

    assert_equal [Date.new(2026, 6, 14), Date.new(2026, 6, 15)], breakfast_dates
  end

  private

  def create_breakfast_service(filial, region: nil)
    Service.create!(
      name: "Café da Manhã",
      price: 80,
      filial: filial,
      region: region || filial.region || "SP",
      user: create_user("breakfast-service-#{filial.id}-#{region || filial.region || 'sp'}@example.com")
    )
  end

  def create_user(email)
    User.create!(
      email: email,
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
  end

  def breakfast_service_for(reserva)
    breakfast_services_for(reserva).first
  end

  def breakfast_services_for(reserva)
    reserva.reload.reserva_services.includes(:service).select do |reserva_service|
      BreakfastServicesAssigner.breakfast_service?(reserva_service.service)
    end
  end

  def active_breakfast_services_for(reserva)
    breakfast_services_for(reserva).select(&:active?)
  end
end
