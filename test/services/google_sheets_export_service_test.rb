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
end
