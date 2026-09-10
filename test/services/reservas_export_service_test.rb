require 'test_helper'

class ReservasExportServiceTest < ActiveSupport::TestCase
  test 'appends real guest details after the existing group column' do
    reserva = reservas(:one)
    reserva.update_columns(
      group_created: true,
      guest_name: 'Bruna Ferreira',
      guest_phone: '11999999999'
    )

    exporter = ReservasExportService.new(Reserva.where(id: reserva.id))
    headers = exporter.send(:headers)
    rows = exporter.generate_array

    assert_equal 'Grupo Criado', headers[20]
    assert_equal 'Nome Real do Hóspede', headers[21]
    assert_equal 'Telefone Real do Hóspede', headers[22]
    assert_equal 'PDF Fotos', headers[23]

    rows.each do |row|
      assert_equal 'Sim', row[20]
      assert_equal 'Bruna Ferreira', row[21]
      assert_equal '11999999999', row[22]
      assert_equal '-', row[23]
    end
  end

  test 'exports operational services with stable id and status' do
    service_date = Date.current + 5.days
    occurrence = OperationalServiceOccurrence.create!(
      cabana: cabanas(:one),
      filial: filials(:one),
      stable_id: "fake-holmy-mystring-#{service_date.iso8601}-entry",
      kind: FakeHolmyCleaningSync::KIND,
      event_type: FakeHolmyCleaningSync::ENTRY_TYPE,
      name: FakeHolmyCleaningSync::ENTRY_NAME,
      service_date: service_date
    )

    exporter = ReservasExportService.new(Reserva.none, include_operational_services: true)
    row = exporter.generate_array.find { |exported_row| exported_row[1] == occurrence.stable_id }

    assert row
    assert_equal 'Serviço', row[0]
    assert_equal FakeHolmyCleaningSync::ENTRY_NAME, row[12]
    assert_equal service_date.strftime('%d/%m/%Y'), row[13]
    assert_equal 'Ativo', row[15]
  end

  test 'exports recurring maintenance as maintenance operational service' do
    service_date = Date.current + 8.days
    occurrence = OperationalServiceOccurrence.create!(
      cabana: cabanas(:one),
      filial: filials(:one),
      stable_id: "recurring-maintenance-rule-12-cabana-#{cabanas(:one).id}-#{service_date.iso8601}",
      kind: 'recurring_maintenance',
      event_type: 'maintenance',
      name: 'Olhar estrada',
      service_date: service_date
    )

    exporter = ReservasExportService.new(Reserva.none, include_operational_services: true)
    row = exporter.generate_array.find { |exported_row| exported_row[1] == occurrence.stable_id }

    assert row
    assert_equal 'Serviço', row[0]
    assert_equal cabanas(:one).name, row[2]
    assert_equal 'Manutenção', row[4]
    assert_equal 'Olhar estrada', row[12]
    assert_equal service_date.strftime('%d/%m/%Y'), row[13]
    assert_equal 'Ativo', row[15]
  end
end
