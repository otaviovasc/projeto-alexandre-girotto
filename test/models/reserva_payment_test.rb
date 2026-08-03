require "test_helper"

class ReservaPaymentTest < ActiveSupport::TestCase
  test "defaults to six credit card installments" do
    payment = ReservaPayment.new

    payment.valid?

    assert_equal 6, payment.max_credit_card_installments
  end

  test "validates credit card installment range" do
    payment = ReservaPayment.new(max_credit_card_installments: 13)

    payment.valid?

    assert payment.errors.of_kind?(:max_credit_card_installments, :inclusion)
  end

  test "guest visible deadline keeps one hour as operational buffer" do
    created_at = Time.zone.parse("2026-07-25 12:00")
    payment = ReservaPayment.new(
      created_at: created_at,
      due_at: created_at + 3.hours
    )

    assert_equal created_at + 2.hours, payment.guest_visible_due_at
    assert_equal "2 horas", payment.guest_visible_hold_label
  end

  test "guest visible deadline does not move before creation time" do
    created_at = Time.zone.parse("2026-07-25 12:00")
    payment = ReservaPayment.new(
      created_at: created_at,
      due_at: created_at + 30.minutes
    )

    assert_equal created_at + 30.minutes, payment.guest_visible_due_at
    assert_equal "30 minutos", payment.guest_visible_hold_label
  end

  test "public booking keeps real checkout deadline" do
    created_at = Time.zone.parse("2026-07-25 12:00")
    payment = ReservaPayment.new(
      created_at: created_at,
      due_at: created_at + 15.minutes,
      public_booking_payload: { source: "public_booking" }
    )

    assert_equal created_at + 15.minutes, payment.guest_visible_due_at
    assert_nil payment.guest_visible_hold_label
  end

  test "late online payment does not confirm reservation" do
    filial = Filial.create!(name: "Filial pagamento tarde")
    cabana = Cabana.create!(name: "Cabana pagamento tarde", price: 100, filial: filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: users(:one),
      start_date: Date.current + 2.months,
      end_date: Date.current + 2.months + 2.days,
      payment_status: "canceled",
      blocks_availability: false,
      total_price: 100
    )
    payment = reserva.reserva_payments.create!(
      installment_number: 1,
      amount: 100,
      due_at: 1.hour.ago,
      payment_status: "canceled",
      payment_order_code: "RP#{reserva.id}LATE"
    )

    GoogleSheetsExportService.stub(:configured?, false) do
      ReservaPaymentProcessor.call(reserva_payment: payment, status: "paid", source: "cielo_sync")
    end

    assert payment.reload.late_paid?
    assert reserva.reload.canceled?
    assert_not reserva.blocks_availability?
  end
end
