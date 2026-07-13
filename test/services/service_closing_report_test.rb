require "test_helper"

class ServiceClosingReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "brauna meals discount delivery by period and pay rubinho per period" do
    travel_to Time.zone.local(2026, 7, 13, 12) do
      filial = Filial.create!(name: "Fattoria di Brauna")
      cabana = Cabana.create!(name: "Zucchero", price: 100, filial: filial)
      reserva = create_reserva(cabana, "closing@example.com", Date.new(2026, 6, 9), Date.new(2026, 6, 12))

      create_reserva_service(reserva, "Café da Manhã", 98, Date.new(2026, 6, 10))
      create_reserva_service(reserva, "Jantar", 95, Date.new(2026, 6, 10))
      create_reserva_service(reserva, "Tábua de frios", 130, Date.new(2026, 6, 11))

      report = ServiceClosingReport.new(month: Date.new(2026, 6, 1))
      providers = report.filial_reports.first[:providers].index_by { |row| row[:provider] }

      assert_equal 133.to_d, providers.fetch("Andreia")[:total]
      assert_equal 100.to_d, providers.fetch("Maykha")[:total]
      assert_equal 90.to_d, providers.fetch("Rubinho")[:total]
    end
  end

  private

  def create_reserva(cabana, email, start_date, end_date)
    Reserva.create!(
      cabana: cabana,
      user: create_user(email),
      start_date: start_date,
      end_date: end_date,
      payment_status: "paid",
      blocks_availability: true,
      total_price: 0
    )
  end

  def create_reserva_service(reserva, name, partner_price, service_date)
    service = Service.create!(
      name: name,
      price: partner_price,
      partner_price: partner_price,
      filial: reserva.cabana.filial,
      user: create_user("#{name.parameterize}-provider@example.com")
    )

    ReservaService.create!(
      reserva: reserva,
      service: service,
      service_date: service_date,
      quantity: 1
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
end
