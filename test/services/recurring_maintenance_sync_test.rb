require 'test_helper'

class RecurringMaintenanceSyncTest < ActiveSupport::TestCase
  setup do
    ReservationWhatsappTask.delete_all
    OperationalServiceOccurrence.delete_all
    RecurringMaintenanceRule.delete_all

    @filial = Filial.create!(name: 'Serra da Mantiqueira')
    @cabana = Cabana.create!(name: 'Collina - Serra da Mantiqueira', filial: @filial, price: 799)
    @user = User.create!(name: 'Teste', email: "recurring-maintenance-#{object_id}@example.com", password: 'password')
    @cleaning_service = Service.create!(
      name: '➡️ Limpeza Entrada (MG)',
      filial: @filial,
      user: @user,
      price: 0,
      partner_price: 0
    )
  end

  test 'creates active operational occurrence on target date when there is no nearby cleaning' do
    rule = create_rule(first_due_on: Date.new(2026, 9, 15))

    result = RecurringMaintenanceSync.run(
      start_date: Date.new(2026, 9, 10),
      end_date: Date.new(2026, 9, 20)
    )

    assert_equal 1, result.created
    occurrence = OperationalServiceOccurrence.find_by!(kind: 'recurring_maintenance')
    assert_equal @cabana, occurrence.cabana
    assert_equal @filial, occurrence.filial
    assert_equal 'Olhar estrada', occurrence.name
    assert_equal Date.new(2026, 9, 15), occurrence.service_date
    assert_equal "recurring-maintenance-rule-#{rule.id}-cabana-#{@cabana.id}-target-2026-09-15", occurrence.stable_id
    assert occurrence.active?
  end

  test 'aligns operational occurrence with nearby real cleaning' do
    rule = create_rule(first_due_on: Date.new(2026, 9, 15))
    add_real_cleaning_on(Date.new(2026, 9, 18))

    result = RecurringMaintenanceSync.run(
      start_date: Date.new(2026, 9, 10),
      end_date: Date.new(2026, 9, 20)
    )

    assert_equal 1, result.created
    occurrence = OperationalServiceOccurrence.find_by!(kind: 'recurring_maintenance')
    assert_equal Date.new(2026, 9, 18), occurrence.service_date
    assert_equal "recurring-maintenance-rule-#{rule.id}-cabana-#{@cabana.id}-target-2026-09-15", occurrence.stable_id
  end

  test 'aligns with nearby fake holmy cleaning and prefers earlier date on tie' do
    rule = create_rule(first_due_on: Date.new(2026, 9, 15))
    add_real_cleaning_on(Date.new(2026, 9, 17))
    add_fake_holmy_cleaning_on(Date.new(2026, 9, 13))

    result = RecurringMaintenanceSync.run(
      start_date: Date.new(2026, 9, 10),
      end_date: Date.new(2026, 9, 20)
    )

    assert_equal 1, result.created
    occurrence = OperationalServiceOccurrence.find_by!(kind: 'recurring_maintenance')
    assert_equal Date.new(2026, 9, 13), occurrence.service_date
    assert_equal "recurring-maintenance-rule-#{rule.id}-cabana-#{@cabana.id}-target-2026-09-15", occurrence.stable_id
  end

  test 'cancels obsolete occurrence when rule is paused' do
    rule = create_rule(first_due_on: Date.new(2026, 9, 15))
    RecurringMaintenanceSync.run(start_date: Date.new(2026, 9, 10), end_date: Date.new(2026, 9, 20))
    occurrence = OperationalServiceOccurrence.find_by!(kind: 'recurring_maintenance')

    rule.update!(active: false)
    result = RecurringMaintenanceSync.run(start_date: Date.new(2026, 9, 10), end_date: Date.new(2026, 9, 20))

    assert_equal 1, result.cancelled
    assert occurrence.reload.cancelled?
    assert_equal 'Manutenção recorrente removida, pausada ou alterada.', occurrence.cancellation_reason
  end

  private

  def create_rule(attributes = {})
    RecurringMaintenanceRule.create!({
      title: 'Olhar estrada',
      message_body: 'Oi {{nome}}, olhar {{titulo}} na {{cabana}} dia {{data_curta}}.',
      recipients_text: 'Bruna | 35999999999',
      frequency_interval: 1,
      frequency_unit: 'monthly',
      first_due_on: Date.current + 1.day,
      cabana_ids: [@cabana.id]
    }.merge(attributes))
  end

  def add_real_cleaning_on(date)
    @cleaning_anchor_counter ||= 0
    anchor_start = Date.new(2026, 12, 10) + @cleaning_anchor_counter.days
    @cleaning_anchor_counter += 3

    reserva = Reserva.create!(
      cabana: @cabana,
      user: @user,
      start_date: anchor_start,
      end_date: anchor_start + 1.day,
      payment_status: 'paid',
      blocks_availability: true,
      total_price: 1000
    )
    reserva.reserva_services.create!(
      service: @cleaning_service,
      service_date: date,
      quantity: 1
    )
  end

  def add_fake_holmy_cleaning_on(date)
    OperationalServiceOccurrence.create!(
      stable_id: "fake-holmy-cabana-#{@cabana.id}-#{date.iso8601}-entry",
      kind: FakeHolmyCleaningSync::KIND,
      event_type: FakeHolmyCleaningSync::ENTRY_TYPE,
      name: FakeHolmyCleaningSync::ENTRY_NAME,
      service_date: date,
      cabana: @cabana,
      filial: @filial,
      status: 'active'
    )
  end
end
