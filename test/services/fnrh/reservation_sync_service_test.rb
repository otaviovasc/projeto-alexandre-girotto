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

    test 'creates a mock FNRH reservation when group is ready even with zero price' do
      reserva = create_reserva(group_created: true, total_price: 0)

      assert ReservationSyncService.new(reserva).call(force: true)

      reserva.reload
      assert_equal 'awaiting_precheckin', reserva.fnrh_status
      assert reserva.fnrh_reservation_id.present?
      assert_equal "/fnrh-simulacao/precheckin/#{reserva.fnrh_reservation_id}", reserva.fnrh_precheckin_url
      assert reserva.fnrh_scheduled_checkin_at.present?
      assert_equal 'reservation_created', reserva.fnrh_events.last.event_type
    end

    test 'does not create FNRH reservation without group' do
      reserva = create_reserva(group_created: false, total_price: 0)

      assert_not ReservationSyncService.new(reserva).call(force: true)
      assert_nil reserva.reload.fnrh_reservation_id
      assert_equal 'not_eligible', reserva.fnrh_status
    end

    test 'does not create FNRH reservation for partnership observation' do
      reserva = create_reserva(group_created: true, total_price: 500, observation: 'Parceria')

      assert_not ReservationSyncService.new(reserva).call(force: true)
      assert_nil reserva.reload.fnrh_reservation_id
      assert_equal 'not_eligible', reserva.fnrh_status
    end

    test 'does not create FNRH reservation for partner guest' do
      @user.update!(partner: true)
      reserva = create_reserva(group_created: true, total_price: 500)

      assert_not ReservationSyncService.new(reserva).call(force: true)
      assert_nil reserva.reload.fnrh_reservation_id
      assert_equal 'not_eligible', reserva.fnrh_status
    end

    test 'does not create FNRH reservation for partnership creator' do
      creator = User.create!(
        name: 'Milena Parcerias',
        email: 'milena-fnrh@example.com',
        password: 'password123',
        role: :partnership_agent
      )
      reserva = create_reserva(group_created: true, total_price: 500, partnership_creator: creator)

      assert_not ReservationSyncService.new(reserva).call(force: true)
      assert_nil reserva.reload.fnrh_reservation_id
      assert_equal 'not_eligible', reserva.fnrh_status
    end

    test 'creates a mock FNRH reservation when group is ready' do
      reserva = create_reserva(group_created: true, total_price: 500)

      assert ReservationSyncService.new(reserva).call(force: true)

      reserva.reload
      assert_equal 'awaiting_precheckin', reserva.fnrh_status
      assert reserva.fnrh_reservation_id.present?
      assert_equal "/fnrh-simulacao/precheckin/#{reserva.fnrh_reservation_id}", reserva.fnrh_precheckin_url
      assert reserva.fnrh_scheduled_checkin_at.present?
      assert_equal 'reservation_created', reserva.fnrh_events.last.event_type
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

    test 'pauses reservation when FNRH says the reservation code already exists' do
      reserva = create_reserva(group_created: true, total_price: 500)
      fake_client = Object.new
      fake_client.define_singleton_method(:create_reservation) do |_reserva|
        raise 'FNRH 400: {"message":"Já existe uma reserva com o código informado."}'
      end

      Fnrh::Client.stub(:build, fake_client) do
        assert_not ReservationSyncService.new(reserva).call(force: true)
      end

      reserva.reload
      assert_nil reserva.fnrh_reservation_id
      assert_equal 'duplicate_in_fnrh', reserva.fnrh_status
      assert_includes reserva.fnrh_last_error, 'Já existe uma reserva'
      assert_equal 'duplicate_reservation', reserva.fnrh_events.last.event_type
    end

    private

    def create_reserva(group_created:, total_price:, observation: 'Sistema', partnership_creator: nil)
      Reserva.create!(
        cabana: @cabana,
        user: @user,
        start_date: Date.current + 10.days,
        end_date: Date.current + 12.days,
        payment_status: 'paid',
        group_created: group_created,
        total_price: total_price,
        observation: observation,
        partnership_creator: partnership_creator
      )
    end
  end
end
