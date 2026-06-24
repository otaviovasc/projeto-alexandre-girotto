require 'test_helper'

module Fnrh
  class AutomationJobTest < ActiveSupport::TestCase
    setup do
      filial = Filial.create!(name: 'Fattoria di Brauna', region: 'SP')
      cabana = Cabana.create!(name: 'Zucchero - Teste FNRH', price: 100, filial: filial)
      user = User.create!(
        name: 'Hospede Automacao',
        email: 'fnrh-automation@example.com',
        password: 'password123'
      )
      @reserva = Reserva.create!(
        cabana: cabana,
        user: user,
        start_date: Date.current + 10.days,
        end_date: Date.current + 12.days,
        payment_status: 'paid',
        group_created: true,
        total_price: 700
      )
      ReservationSyncService.new(@reserva).call(force: true)
    end

    test 'checks in automatically after the stored scheduled time' do
      scheduled_at = @reserva.reload.fnrh_scheduled_checkin_at
      TransitionService.new(@reserva, source: 'guest').complete_precheckin(at: scheduled_at - 1.hour)

      AutomationJob.run(now: scheduled_at + 1.minute)

      assert_equal 'checked_in', @reserva.reload.fnrh_status
      assert_equal 'automatic', @reserva.fnrh_events.where(event_type: 'checkin').last.source
    end

    test 'creates an eligible reservation that was not synchronized by a callback' do
      unsynced = Reserva.create!(
        cabana: @reserva.cabana,
        user: @reserva.user,
        start_date: Date.current + 20.days,
        end_date: Date.current + 22.days,
        payment_status: 'paid',
        group_created: true,
        total_price: 800
      )

      AutomationJob.run

      assert_equal 'awaiting_precheckin', unsynced.reload.fnrh_status
      assert unsynced.fnrh_reservation_id.present?
    end

    test 'cancels an external reservation after a confirmed local cancellation' do
      @reserva.update_column(:payment_status, 'canceled')

      AutomationJob.run

      assert_equal 'cancelled', @reserva.reload.fnrh_status
      assert_equal 'automatic', @reserva.fnrh_events.where(event_type: 'cancellation').last.source
    end

    test 'does not check in a no-show reservation' do
      scheduled_at = @reserva.reload.fnrh_scheduled_checkin_at
      TransitionService.new(@reserva, source: 'guest').complete_precheckin(at: scheduled_at - 1.hour)
      TransitionService.new(@reserva, source: 'manual').no_show(at: scheduled_at - 5.minutes)

      AutomationJob.run(now: scheduled_at + 1.minute)

      assert_equal 'no_show', @reserva.reload.fnrh_status
      assert_equal 0, @reserva.fnrh_events.where(event_type: 'checkin').count
    end

    test 'keeps awaiting precheckin before the checkout deadline' do
      checkout_at = Schedule.checkout_at(@reserva)

      AutomationJob.run(now: checkout_at - 1.minute)

      assert_equal 'awaiting_precheckin', @reserva.reload.fnrh_status
      assert_equal 0, @reserva.fnrh_events.where(event_type: 'no_show').count
    end

    test 'marks awaiting precheckin as no-show after the checkout deadline' do
      checkout_at = Schedule.checkout_at(@reserva)

      AutomationJob.run(now: checkout_at + 1.minute)

      assert_equal 'no_show', @reserva.reload.fnrh_status
      assert_equal 'automatic', @reserva.fnrh_events.where(event_type: 'no_show').last.source
      assert_equal 0, @reserva.fnrh_events.where(event_type: 'checkin').count
      assert_equal 0, @reserva.fnrh_events.where(event_type: 'checkout').count
    end

    test 'checks out automatically at the configured checkout time' do
      TransitionService.new(@reserva, source: 'manual').check_in(at: @reserva.start_date.in_time_zone)
      checkout_at = Schedule.checkout_at(@reserva)

      AutomationJob.run(now: checkout_at + 1.minute)

      assert_equal 'checked_out', @reserva.reload.fnrh_status
      assert_equal 'automatic', @reserva.fnrh_events.where(event_type: 'checkout').last.source
    end
  end
end
