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

  test "service purchase override can use selected date through checkout" do
    reserva = Reserva.new(
      start_date: Date.new(2026, 1, 26),
      end_date: Date.new(2026, 1, 28),
      service_purchase_override: true,
      service_purchase_override_until: Date.new(2026, 1, 28)
    )

    assert reserva.service_purchase_window_open?(Date.new(2026, 1, 26))
    assert reserva.service_purchase_window_open?(Date.new(2026, 1, 28))
    assert_not reserva.service_purchase_window_open?(Date.new(2026, 1, 29))
  end

  test "service purchase late fee applies after normal deadline unless waived" do
    reserva = Reserva.new(
      start_date: Date.new(2026, 1, 26),
      end_date: Date.new(2026, 1, 28),
      service_purchase_override: true,
      service_purchase_override_until: Date.new(2026, 1, 28)
    )

    assert_equal BigDecimal("50"), reserva.service_purchase_late_fee_amount(Date.new(2026, 1, 20))

    reserva.service_purchase_late_fee_waived = true

    assert_equal 0.to_d, reserva.service_purchase_late_fee_amount(Date.new(2026, 1, 20))
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

  test "canceling a reservation preserves history and releases operation" do
    filial = Filial.create!(name: "Filial cancelamento")
    cabana = Cabana.create!(name: "Cabana cancelamento", price: 100, filial: filial)
    reserva = create_reserva(cabana, "cancel-history@example.com", Date.new(2028, 1, 10), Date.new(2028, 1, 12))
    service = Service.create!(
      name: "Jantar",
      price: 109,
      partner_price: 95,
      filial: filial,
      user: create_user("provider-cancel@example.com")
    )
    reserva_service = ReservaService.create!(
      reserva: reserva,
      service: service,
      service_date: Date.new(2028, 1, 10),
      quantity: 1
    )
    admin = create_user("admin-cancel@example.com")

    reserva.cancel_for_operations!(by: admin, reason: "Teste")

    assert reserva.reload.canceled?
    assert_not reserva.blocks_availability?
    assert_equal admin, reserva.canceled_by
    assert_equal "Teste", reserva.cancellation_reason
    assert reserva.canceled_at.present?
    assert reserva_service.reload.cancelled?
    assert_not_includes Reserva.integration_ready, reserva

    candidate = Reserva.new(
      cabana: cabana,
      user: create_user("free-after-cancel@example.com"),
      start_date: Date.new(2028, 1, 10),
      end_date: Date.new(2028, 1, 12),
      payment_status: "paid",
      blocks_availability: true,
      total_price: 0
    )
    assert candidate.valid?
  end

  test "external canceled history ignores unpaid pre reservations" do
    filial = Filial.create!(name: "Filial pre reserva")
    cabana = Cabana.create!(name: "Cabana pre reserva", price: 100, filial: filial)
    real_canceled = create_reserva(cabana, "real-canceled@example.com", Date.new(2028, 2, 10), Date.new(2028, 2, 12))
    unpaid_pre_reservation = Reserva.create!(
      cabana: cabana,
      user: create_user("unpaid-pre-reservation@example.com"),
      start_date: Date.new(2028, 3, 10),
      end_date: Date.new(2028, 3, 12),
      payment_status: "waiting_payment",
      blocks_availability: true,
      total_price: 100,
      payment_expires_at: 1.hour.from_now
    )
    unpaid_pre_reservation.reserva_payments.create!(
      installment_number: 1,
      amount: 100,
      due_at: 1.hour.from_now,
      payment_order_code: "RP#{unpaid_pre_reservation.id}1TEST"
    )

    real_canceled.cancel_for_operations!(by: nil, reason: "Cancelamento real")
    unpaid_pre_reservation.cancel_for_operations!(by: nil, reason: "Primeira parcela vencida sem pagamento.")

    assert_includes Reserva.canceled_for_history, unpaid_pre_reservation
    assert_includes Reserva.canceled_for_external_history, real_canceled
    assert_not_includes Reserva.canceled_for_external_history, unpaid_pre_reservation
    assert_includes Reserva.unfinished_pre_reservations, unpaid_pre_reservation
    assert_not_includes Reserva.unfinished_pre_reservations, real_canceled
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
