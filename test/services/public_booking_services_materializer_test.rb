require "test_helper"

class PublicBookingServicesMaterializerTest < ActiveSupport::TestCase
  setup do
    @filial = Filial.create!(name: "Serra da Mantiqueira")
    @cabana = Cabana.create!(name: "Nuvolo - Serra da Mantiqueira", price: 500, filial: @filial)
    @user = create_user("public-booking-materializer@example.com")
  end

  test "assigns breakfast and lunch to checkout day on one night stays" do
    reserva = create_reserva(start_date: Date.new(2027, 7, 27), end_date: Date.new(2027, 7, 28))
    cafe = create_service("Cafe da Manha")
    almoco = create_service("Almoco")
    payment = create_payment(reserva, [
      service_payload(cafe, quantity: 1),
      service_payload(almoco, quantity: 1)
    ])

    PublicBookingServicesMaterializer.call(payment)

    assert_equal [Date.new(2027, 7, 28)], service_dates(reserva, cafe)
    assert_equal [Date.new(2027, 7, 28)], service_dates(reserva, almoco)
  end

  test "spreads repeated breakfasts over each morning" do
    reserva = create_reserva(start_date: Date.new(2027, 7, 27), end_date: Date.new(2027, 7, 29))
    cafe = create_service("Cafe da Manha")
    payment = create_payment(reserva, [service_payload(cafe, quantity: 2)])

    PublicBookingServicesMaterializer.call(payment)

    assert_equal [Date.new(2027, 7, 28), Date.new(2027, 7, 29)], service_dates(reserva, cafe)
  end

  test "creates one reservation service per purchased unit" do
    reserva = create_reserva(start_date: Date.new(2027, 7, 27), end_date: Date.new(2027, 7, 28))
    jantar = create_service("Jantar")
    payment = create_payment(reserva, [service_payload(jantar, quantity: 2)])

    PublicBookingServicesMaterializer.call(payment)

    purchased_services = reserva.reserva_services.where(service: jantar).order(:id)
    assert_equal 2, purchased_services.count
    assert_equal [1, 1], purchased_services.pluck(:quantity)
    assert_equal [Date.new(2027, 7, 27), Date.new(2027, 7, 27)], purchased_services.pluck(:service_date)
  end

  test "assigns arrival and evening services from checkin" do
    reserva = create_reserva(start_date: Date.new(2027, 7, 27), end_date: Date.new(2027, 7, 29))
    espumante = create_service("Espumante")
    jantar = create_service("Jantar")
    payment = create_payment(reserva, [
      service_payload(espumante, quantity: 1),
      service_payload(jantar, quantity: 2)
    ])

    PublicBookingServicesMaterializer.call(payment)

    assert_equal [Date.new(2027, 7, 27)], service_dates(reserva, espumante)
    assert_equal [Date.new(2027, 7, 27), Date.new(2027, 7, 28)], service_dates(reserva, jantar)
  end

  test "separates board from dinner when the stay has another night" do
    reserva = create_reserva(start_date: Date.new(2027, 7, 27), end_date: Date.new(2027, 7, 29))
    jantar = create_service("Jantar")
    tabua = create_service("Tabua de Frios")
    payment = create_payment(reserva, [
      service_payload(tabua, quantity: 1),
      service_payload(jantar, quantity: 1)
    ])

    PublicBookingServicesMaterializer.call(payment)

    assert_equal [Date.new(2027, 7, 27)], service_dates(reserva, jantar)
    assert_equal [Date.new(2027, 7, 28)], service_dates(reserva, tabua)
  end

  private

  def create_user(email)
    User.create!(
      name: email.split("@").first,
      email: email,
      password: "password123",
      telephone: SecureRandom.random_number(10**11).to_s.rjust(11, "0")
    )
  end

  def create_reserva(start_date:, end_date:)
    Reserva.create!(
      cabana: @cabana,
      user: @user,
      start_date: start_date,
      end_date: end_date,
      payment_status: "paid",
      total_price: 1000
    )
  end

  def create_service(name)
    Service.create!(
      name: name,
      description: name,
      price: 100,
      partner_price: 80,
      filial: @filial,
      user: @user,
      show_in_marketplace: true
    )
  end

  def create_payment(reserva, services)
    ReservaPayment.create!(
      reserva: reserva,
      installment_number: 1,
      amount: services.sum { |service| BigDecimal(service["total"].to_s) },
      due_at: 1.day.from_now,
      payment_status: "paid",
      paid_at: Time.current,
      payment_order_code: "PB#{SecureRandom.hex(8)}",
      public_booking_payload: {
        "source" => "public_booking",
        "daily_total" => "0",
        "services_total" => services.sum { |service| BigDecimal(service["total"].to_s) }.to_s,
        "services" => services
      }
    )
  end

  def service_payload(service, quantity:)
    {
      "service_id" => service.id,
      "name" => service.name,
      "quantity" => quantity,
      "unit_price" => service.price.to_s,
      "total" => (service.price * quantity).to_s,
      "date_pending" => true
    }
  end

  def service_dates(reserva, service)
    reserva.reserva_services
           .where(service: service)
           .order(:service_date, :id)
           .pluck(:service_date)
  end
end
