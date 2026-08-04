require "test_helper"

class GoogleSheetsExportServiceTest < ActiveSupport::TestCase
  FakeReservation = Struct.new(:ready) do
    def integration_ready?
      ready
    end
  end

  test "export excludes reservations that are not confirmed" do
    pending = FakeReservation.new(false)
    confirmed = FakeReservation.new(true)
    exported = nil
    exporter = Object.new
    exporter.define_singleton_method(:export) do |reservations|
      exported = reservations
      { success: true }
    end

    GoogleSheetsExportService.stub(:new, exporter) do
      GoogleSheetsExportService.export_reservas([pending, confirmed])
    end

    assert_equal [confirmed], exported
  end

  test "canceled history spreadsheet uses separate default id" do
    assert_equal(
      GoogleSheetsExportService::DEFAULT_CANCELED_HISTORY_SPREADSHEET_ID,
      GoogleSheetsExportService.canceled_history_spreadsheet_id
    )
  end

  test "canceled history spreadsheet id can be configured by env" do
    previous_value = ENV['GOOGLE_SHEETS_CANCELED_SPREADSHEET_ID']
    ENV['GOOGLE_SHEETS_CANCELED_SPREADSHEET_ID'] = 'custom-canceled-history-sheet'

    assert_equal 'custom-canceled-history-sheet', GoogleSheetsExportService.canceled_history_spreadsheet_id
  ensure
    ENV['GOOGLE_SHEETS_CANCELED_SPREADSHEET_ID'] = previous_value
  end

  test "legacy canceled reservation rows keep detailed services and cancellation metadata" do
    canceled_at = Time.find_zone('America/Sao_Paulo').local(2026, 8, 3, 20, 22)
    reserva = reservas(:one)
    reserva.update_columns(
      payment_status: 'canceled',
      canceled_at: canceled_at,
      canceled_by_id: users(:two).id,
      cancellation_reason: 'Cancelamento teste'
    )
    reserva_services(:one).update_columns(
      service_date: Date.new(2026, 8, 5),
      status: 'cancelled'
    )

    exporter = GoogleSheetsExportService.new
    headers = exporter.send(:legacy_canceled_reservas_headers)
    rows = exporter.send(:legacy_canceled_reservas_rows, Reserva.where(id: reserva.id))

    assert_equal 'Data Cancelamento', headers[-3]
    assert_equal 2, rows.size
    assert_equal ['Reserva', 'Serviço'], rows.map(&:first)
    rows.each do |row|
      assert_equal '03/08/2026 20:22', row[-3]
      assert_equal 'Usuario Teste Dois', row[-2]
      assert_equal 'Cancelamento teste', row[-1]
    end
    assert_equal 'Cancelado', rows.second[15]
  end
end
