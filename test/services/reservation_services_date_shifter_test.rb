require "test_helper"
require "securerandom"

class ReservationServicesDateShifterTest < ActiveSupport::TestCase
  test "moves normal services by their position in the stay when dates change" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(name: "Zucchero", price: 100, filial: filial)
    user = create_user("shift-services@example.com")
    reserva = create_reserva(cabana, user, Date.new(2026, 6, 9), Date.new(2026, 6, 11))
    jantar = create_service("Jantar", filial)
    espumante = create_service("Espumante", filial)
    cafe = create_service("Café da Manhã", filial)
    almoco = create_service("Almoço", filial)

    create_reserva_service(reserva, jantar, Date.new(2026, 6, 9))
    create_reserva_service(reserva, espumante, Date.new(2026, 6, 9))
    create_reserva_service(reserva, cafe, Date.new(2026, 6, 10))
    create_reserva_service(reserva, almoco, Date.new(2026, 6, 11))

    reserva.update!(start_date: Date.new(2026, 8, 15), end_date: Date.new(2026, 8, 17))

    assert_equal Date.new(2026, 8, 15), service_date_for(reserva, jantar)
    assert_equal Date.new(2026, 8, 15), service_date_for(reserva, espumante)
    assert_equal Date.new(2026, 8, 16), service_date_for(reserva, cafe)
    assert_equal Date.new(2026, 8, 17), service_date_for(reserva, almoco)
  end

  test "keeps normal services when only the checkout is extended" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(name: "Zucchero", price: 100, filial: filial)
    user = create_user("extend-services@example.com")
    reserva = create_reserva(cabana, user, Date.new(2026, 6, 9), Date.new(2026, 6, 11))
    jantar = create_service("Jantar", filial)
    espumante = create_service("Espumante", filial)
    cafe = create_service("Café da Manhã", filial)
    almoco = create_service("Almoço", filial)

    create_reserva_service(reserva, jantar, Date.new(2026, 6, 9))
    create_reserva_service(reserva, espumante, Date.new(2026, 6, 9))
    create_reserva_service(reserva, cafe, Date.new(2026, 6, 10))
    create_reserva_service(reserva, almoco, Date.new(2026, 6, 11))

    reserva.update!(end_date: Date.new(2026, 6, 12))

    assert_equal Date.new(2026, 6, 9), service_date_for(reserva, jantar)
    assert_equal Date.new(2026, 6, 9), service_date_for(reserva, espumante)
    assert_equal Date.new(2026, 6, 10), service_date_for(reserva, cafe)
    assert_equal Date.new(2026, 6, 11), service_date_for(reserva, almoco)
  end

  test "uses the manually adjusted service position on the next date change" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(name: "Zucchero", price: 100, filial: filial)
    user = create_user("manual-position@example.com")
    reserva = create_reserva(cabana, user, Date.new(2026, 6, 9), Date.new(2026, 6, 11))
    cafe = create_service("Café da Manhã", filial)
    reserva_service = create_reserva_service(reserva, cafe, Date.new(2026, 6, 10))
    reserva_service.update!(service_date: Date.new(2026, 6, 11))

    reserva.update!(start_date: Date.new(2026, 8, 15), end_date: Date.new(2026, 8, 17))

    assert_equal Date.new(2026, 8, 17), service_date_for(reserva, cafe)
  end

  test "does not move cleaning or automatic included breakfast services" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    cabana = Cabana.create!(name: "Zucchero", price: 100, filial: filial)
    user = create_user("skip-special-services@example.com")
    reserva = create_reserva(cabana, user, Date.new(2026, 6, 9), Date.new(2026, 6, 11))
    cleaning = create_service("➡️ Limpeza Entrada (SP)", filial)
    breakfast = create_service("Café da Manhã", filial)
    cleaning_reserva_service = create_reserva_service(reserva, cleaning, Date.new(2026, 6, 9))
    breakfast_reserva_service = create_reserva_service(
      reserva,
      breakfast,
      Date.new(2026, 6, 10),
      observation: BreakfastServicesAssigner::AUTO_OBSERVATION
    )

    ReservationServicesDateShifter.new(
      reserva,
      old_start_date: Date.new(2026, 6, 9),
      new_start_date: Date.new(2026, 8, 15)
    ).call

    assert_equal Date.new(2026, 6, 9), cleaning_reserva_service.reload.service_date
    assert_equal Date.new(2026, 6, 10), breakfast_reserva_service.reload.service_date
  end

  private

  def create_reserva(cabana, user, start_date, end_date)
    Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: start_date,
      end_date: end_date,
      payment_status: "paid",
      total_price: 0
    )
  end

  def create_service(name, filial)
    Service.create!(
      name: name,
      price: 80,
      filial: filial,
      user: create_user("#{name.parameterize}-#{SecureRandom.hex(4)}@example.com")
    )
  end

  def create_reserva_service(reserva, service, service_date, observation: nil)
    reserva.reserva_services.create!(
      service: service,
      quantity: 1,
      service_date: service_date,
      observation: observation
    )
  end

  def service_date_for(reserva, service)
    reserva.reload.reserva_services.find_by!(service: service).service_date
  end

  def create_user(email)
    User.create!(
      email: email,
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
  end
end
