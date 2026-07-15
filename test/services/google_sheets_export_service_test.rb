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
end
