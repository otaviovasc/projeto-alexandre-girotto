require 'test_helper'

module Fnrh
  class ReservationSyncServiceTest < ActiveSupport::TestCase
    setup do
      @filial = Filial.create!(name: 'Serra da Mantiqueira', region: 'MG')
      @cabana = Cabana.create!(name: 'Valle - Teste FNRH', price: 100, filial: @filial)
      @user = User.create!(
        name: 'Hospede Teste',
        email: 'fnrh-sync@example.com',
        password: 'password123'
      )
    end

    test 'creates a mock FNRH reservation when price and group are ready' do
      reserva = create_reserva(group_created: true, total_price: 500)

      assert ReservationSyncService.new(reserva).call(force: true)

      reserva.reload
      assert_equal 'awaiting_precheckin', reserva.fnrh_status
      assert reserva.fnrh_reservation_id.present?
      assert_equal "/fnrh-simulacao/precheckin/#{reserva.fnrh_reservation_id}", reserva.fnrh_precheckin_url
      assert reserva.fnrh_scheduled_checkin_at.present?
      assert_equal 'reservation_created', reserva.fnrh_events.last.event_type
    end

    test 'does not create FNRH reservation without price or group' do
      reserva = create_reserva(group_created: false, total_price: 0)

      assert_not ReservationSyncService.new(reserva).call(force: true)
      assert_nil reserva.reload.fnrh_reservation_id
      assert_equal 'not_eligible', reserva.fnrh_status
    end

    test 'updates the existing FNRH reservation without creating a duplicate' do
      reserva = create_reserva(group_created: true, total_price: 500)
      service = ReservationSyncService.new(reserva)
      service.call(force: true)
      original_id = reserva.reload.fnrh_reservation_id

      reserva.update!(start_date: reserva.start_date + 2.days, end_date: reserva.end_date + 2.days)
      assert service.call(force: true)

      assert_equal original_id, reserva.reload.fnrh_reservation_id
      assert_equal 1, reserva.fnrh_events.where(event_type: 'reservation_created').count
      assert_equal 1, reserva.fnrh_events.where(event_type: 'reservation_updated').count
    end

    private

    def create_reserva(group_created:, total_price:)
      Reserva.create!(
        cabana: @cabana,
        user: @user,
        start_date: Date.current + 10.days,
        end_date: Date.current + 12.days,
        payment_status: 'paid',
        group_created: group_created,
        total_price: total_price
      )
    end
  end
end
