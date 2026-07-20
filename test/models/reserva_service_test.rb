require "test_helper"
require "securerandom"

class ReservaServiceTest < ActiveSupport::TestCase
  test "rejects a new non cleaning service outside the official stay" do
    filial = Filial.create!(name: "Filial serviço", region: "MG")
    cabana = Cabana.create!(name: "Cabana serviço", price: 100, filial: filial)
    user = create_user("service-guest@example.com")
    service = Service.create!(name: "Jantar", price: 100, filial: filial, user: create_user("service-owner@example.com"))
    reserva = Reserva.new(
      cabana: cabana,
      user: user,
      start_date: Date.new(2027, 7, 10),
      end_date: Date.new(2027, 7, 12),
      payment_status: "paid",
      total_price: 0
    )

    reserva_service = ReservaService.new(
      reserva: reserva,
      service: service,
      quantity: 1,
      service_date: Date.new(2027, 7, 13)
    )

    assert_not reserva_service.valid?
    assert_includes reserva_service.errors[:service_date], "deve estar entre o check-in e o check-out da reserva."
  end

  test "allows a service containing cobrar on a date outside the stay" do
    filial = Filial.create!(name: "Filial cobrança", region: "MG")
    cabana = Cabana.create!(name: "Cabana cobrança", price: 100, filial: filial)
    service = Service.create!(
      name: "💰 Lembrete de cobrança da segunda parcela",
      price: 0,
      filial: filial,
      user: create_user("billing-owner@example.com")
    )
    reserva = Reserva.new(
      cabana: cabana,
      user: create_user("billing-guest@example.com"),
      start_date: Date.new(2027, 7, 10),
      end_date: Date.new(2027, 7, 12),
      payment_status: "paid",
      total_price: 0
    )
    reserva_service = ReservaService.new(
      reserva: reserva,
      service: service,
      quantity: 1,
      service_date: Date.new(2027, 6, 1)
    )

    assert reserva_service.valid?
  end

  test "allows guest changes before service purchase deadline" do
    reserva_service = build_purchased_service(
      start_date: Date.new(2027, 7, 20),
      end_date: Date.new(2027, 7, 22)
    )

    assert reserva_service.guest_change_allowed?(Date.new(2027, 7, 1))
  end

  test "blocks guest changes for service bought after deadline through manual release" do
    reserva_service = build_purchased_service(
      start_date: Date.new(2027, 7, 20),
      end_date: Date.new(2027, 7, 22),
      purchased_after_service_deadline: true
    )

    assert_not reserva_service.guest_change_allowed?(Date.new(2027, 7, 15))
    assert_equal(
      'Este serviço foi comprado com liberação especial fora do prazo normal. Alterações devem ser feitas pelo atendimento.',
      reserva_service.guest_change_block_reason(Date.new(2027, 7, 15))
    )
  end

  private

  def create_user(email)
    User.create!(
      email: email,
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
  end

  def build_purchased_service(start_date:, end_date:, purchased_after_service_deadline: false)
    suffix = SecureRandom.hex(4)
    filial = Filial.create!(name: "Filial alteração #{suffix}", region: "MG")
    cabana = Cabana.create!(name: "Cabana alteração #{suffix}", price: 100, filial: filial)
    service = Service.create!(
      name: "Jantar #{suffix}",
      price: 100,
      filial: filial,
      user: create_user("owner-#{suffix}@example.com")
    )
    reserva = Reserva.create!(
      cabana: cabana,
      user: create_user("guest-#{suffix}@example.com"),
      start_date: start_date,
      end_date: end_date,
      payment_status: "paid",
      total_price: 0
    )

    ReservaService.create!(
      reserva: reserva,
      service: service,
      quantity: 1,
      service_date: start_date,
      status: 'active',
      purchased_after_service_deadline: purchased_after_service_deadline
    )
  end
end
