require "test_helper"

class ReservaTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "service purchases close ten days before check in" do
    reserva = Reserva.new(start_date: Date.new(2026, 1, 26))

    assert_equal Date.new(2026, 1, 16), reserva.service_purchase_block_date

    travel_to Time.zone.local(2026, 1, 15, 12) do
      assert reserva.service_purchase_window_open?
    end

    travel_to Time.zone.local(2026, 1, 16, 12) do
      assert_not reserva.service_purchase_window_open?
    end

    travel_to Time.zone.local(2026, 1, 26, 12) do
      assert_not reserva.service_purchase_window_open?
    end
  end

  test "service purchase override stays open through check in" do
    reserva = Reserva.new(
      start_date: Date.new(2026, 1, 26),
      service_purchase_override: true
    )

    assert reserva.service_purchase_window_open?(Date.new(2026, 1, 20))
    assert reserva.service_purchase_window_open?(Date.new(2026, 1, 26))
    assert_not reserva.service_purchase_window_open?(Date.new(2026, 1, 27))
  end

  test "recognizes reservations marked as partnership" do
    assert Reserva.new(user: User.new(partner: true)).partnership_reservation?
    assert Reserva.new(user: User.new(partner: false), partnership_creator_id: 123).partnership_reservation?
    assert_not Reserva.new(user: User.new(partner: false)).partnership_reservation?
  end

  test "uses operational dates without changing official dates" do
    reserva = Reserva.new(
      start_date: Date.new(2027, 8, 10),
      end_date: Date.new(2027, 8, 12),
      early_checkin: true,
      late_checkout: true
    )

    assert_equal Date.new(2027, 8, 10), reserva.start_date
    assert_equal Date.new(2027, 8, 12), reserva.end_date
    assert_equal Date.new(2027, 8, 9), reserva.availability_start_date
    assert_equal Date.new(2027, 8, 13), reserva.availability_end_date
  end

  test "prevents an early check in from occupying an existing previous night" do
    filial = Filial.create!(name: "Filial conflito")
    cabana = Cabana.create!(name: "Cabana conflito", price: 100, filial: filial)
    existing = create_reserva(cabana, "existing@example.com", Date.new(2027, 8, 10), Date.new(2027, 8, 12))
    candidate = Reserva.new(
      cabana: cabana,
      user: create_user("candidate@example.com"),
      start_date: existing.end_date,
      end_date: Date.new(2027, 8, 14),
      early_checkin: true,
      payment_status: "paid",
      total_price: 0
    )

    assert_not candidate.valid?
    assert_includes candidate.errors[:base], "A Cabana está indisponível na data selecionada."
  end

  test "validates an operational extension added manually to an imported reservation" do
    filial = Filial.create!(name: "Filial importada")
    cabana = Cabana.create!(name: "Cabana importada", price: 100, filial: filial)
    existing = create_reserva(cabana, "existing-imported@example.com", Date.new(2027, 9, 10), Date.new(2027, 9, 12))
    imported = Reserva.create!(
      cabana: cabana,
      user: create_user("imported@example.com"),
      start_date: existing.end_date,
      end_date: Date.new(2027, 9, 14),
      origem: 'booking',
      payment_status: "paid",
      total_price: 0
    )

    assert_not imported.update(early_checkin: true)
    assert_includes imported.errors[:early_checkin], "não pode ser ativado porque a diária extra do early check-in já está ocupada."
  end

  test "service installments must stay between one and twelve" do
    reserva = Reserva.new(service_max_installments: 13)

    reserva.valid?

    assert reserva.errors.of_kind?(:service_max_installments, :inclusion)
  end

  test "administrative pending reservation does not block availability" do
    filial = Filial.create!(name: "Filial pendente")
    cabana = Cabana.create!(name: "Cabana pendente", price: 100, filial: filial)
    pending = Reserva.create!(
      cabana: cabana,
      user: create_user("pending@example.com"),
      start_date: Date.new(2027, 10, 10),
      end_date: Date.new(2027, 10, 12),
      payment_status: "pending",
      blocks_availability: false,
      total_price: 0
    )
    candidate = Reserva.new(
      cabana: cabana,
      user: create_user("confirmed@example.com"),
      start_date: pending.start_date,
      end_date: pending.end_date,
      payment_status: "paid",
      blocks_availability: true,
      total_price: 0
    )

    assert candidate.valid?
    assert_not pending.integration_ready?
    assert_not_includes Reserva.integration_ready, pending
  end

  test "pending reservation cannot be confirmed when dates became occupied" do
    filial = Filial.create!(name: "Filial confirmação")
    cabana = Cabana.create!(name: "Cabana confirmação", price: 100, filial: filial)
    pending = Reserva.create!(
      cabana: cabana,
      user: create_user("pending-confirm@example.com"),
      start_date: Date.new(2027, 11, 10),
      end_date: Date.new(2027, 11, 12),
      payment_status: "pending",
      blocks_availability: false,
      total_price: 0
    )
    create_reserva(cabana, "occupied@example.com", pending.start_date, pending.end_date)

    pending.assign_attributes(payment_status: "paid", blocks_availability: true)

    assert_not pending.valid?
    assert_includes pending.errors[:base], "A Cabana está indisponível na data selecionada."
  end

  test "confirmed reservation is ready for external integrations" do
    filial = Filial.create!(name: "Filial integrada")
    cabana = Cabana.create!(name: "Cabana integrada", price: 100, filial: filial)
    confirmed = create_reserva(
      cabana,
      "integration-ready@example.com",
      Date.new(2027, 12, 10),
      Date.new(2027, 12, 12)
    )

    assert confirmed.integration_ready?
    assert_includes Reserva.integration_ready, confirmed
  end

  private

  def create_reserva(cabana, email, start_date, end_date)
    Reserva.create!(
      cabana: cabana,
      user: create_user(email),
      start_date: start_date,
      end_date: end_date,
      payment_status: "paid",
      total_price: 0
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
