require 'test_helper'

class RecurringMaintenanceSyncTest < ActiveSupport::TestCase
  setup do
    ReservationWhatsappTask.delete_all
    OperationalServiceOccurrence.delete_all
    RecurringMaintenanceRule.delete_all

    @filial = Filial.create!(name: 'Serra da Mantiqueira')
    @cabana = Cabana.create!(name: 'Collina - Serra da Mantiqueira', filial: @filial, price: 799)
  end

  test 'creates active operational occurrence with stable id' do
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
    assert_equal "recurring-maintenance-rule-#{rule.id}-cabana-#{@cabana.id}-2026-09-15", occurrence.stable_id
    assert occurrence.active?
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
end
