require 'test_helper'

class RecurringMaintenanceRuleTest < ActiveSupport::TestCase
  setup do
    RecurringMaintenanceRule.delete_all

    @filial = Filial.create!(name: 'Serra da Mantiqueira')
    @cabana = Cabana.create!(name: 'Valle - Serra da Mantiqueira', filial: @filial, price: 799)
  end

  test 'parses recipients with name and phone' do
    rule = build_rule(recipients_text: "Bruna | (35) 99999-9999\nRubinho | 35988888888")

    assert rule.valid?
    assert_equal(
      [
        { name: 'Bruna', phone: '35999999999' },
        { name: 'Rubinho', phone: '35988888888' }
      ],
      rule.recipients
    )
  end

  test 'requires at least one recipient phone' do
    rule = build_rule(recipients_text: 'Bruna')

    assert_not rule.valid?
    assert_includes rule.errors[:recipients_text], 'deve ter nome e telefone. Use uma linha por pessoa: Nome | telefone.'
  end

  test 'calculates monthly occurrence dates from first due date' do
    rule = build_rule(
      frequency_interval: 2,
      frequency_unit: 'monthly',
      first_due_on: Date.new(2026, 9, 10)
    )

    assert_equal(
      [Date.new(2026, 11, 10), Date.new(2027, 1, 10)],
      rule.next_occurrence_dates(from: Date.new(2026, 10, 1), through: Date.new(2027, 1, 31))
    )
  end

  private

  def build_rule(attributes = {})
    RecurringMaintenanceRule.new({
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
