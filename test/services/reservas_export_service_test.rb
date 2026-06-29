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

    rows.each do |row|
      assert_equal 'Sim', row[20]
      assert_equal 'Bruna Ferreira', row[21]
      assert_equal '11999999999', row[22]
    end
  end
end
