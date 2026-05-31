require "test_helper"

class IcalReservationImporterTest < ActiveSupport::TestCase
  setup do
    @filial = Filial.create!(name: "Filial teste")
    @cabana = Cabana.create!(name: "Cabana teste", price: 100, filial: @filial)
  end

  test "imports DTEND as checkout date" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:two-nights@example.com
      DTSTART;VALUE=DATE:20260610
      DTEND;VALUE=DATE:20260612
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva = @cabana.reservas.find_by!(origem: "airbnb")

    assert_equal Date.new(2026, 6, 10), reserva.start_date
    assert_equal Date.new(2026, 6, 12), reserva.end_date
  end

  test "imports an active reservation that started before today" do
    import(<<~ICS, today: Date.new(2026, 6, 11))
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:active@example.com
      DTSTART;VALUE=DATE:20260610
      DTEND;VALUE=DATE:20260612
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    assert_equal 1, @cabana.reservas.where(origem: "airbnb").count
  end

  test "keeps checkout and next checkin as separate reservations" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:first@example.com
      DTSTART;VALUE=DATE:20260610
      DTEND;VALUE=DATE:20260612
      SUMMARY:Reserved
      END:VEVENT
      BEGIN:VEVENT
      UID:second@example.com
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    ranges = @cabana.reservas.where(origem: "airbnb").order(:start_date).pluck(:start_date, :end_date)

    assert_equal [[Date.new(2026, 6, 10), Date.new(2026, 6, 12)],
                  [Date.new(2026, 6, 12), Date.new(2026, 6, 14)]], ranges
  end

  test "converts datetime events using the application time zone" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:timezone@example.com
      DTSTART:20260612T000000Z
      DTEND:20260613T000000Z
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva = @cabana.reservas.find_by!(ical_uid: "timezone@example.com")

    assert_equal Date.new(2026, 6, 11), reserva.start_date
    assert_equal Date.new(2026, 6, 12), reserva.end_date
  end

  test "does not overwrite manually edited imported reservation dates" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:manual@example.com
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva = @cabana.reservas.find_by!(ical_uid: "manual@example.com")
    reserva.update!(
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 15),
      manual_override: true
    )

    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:manual@example.com
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva.reload

    assert_equal Date.new(2026, 6, 12), reserva.start_date
    assert_equal Date.new(2026, 6, 15), reserva.end_date
    assert_equal Date.new(2026, 6, 12), reserva.imported_start_date
    assert_equal Date.new(2026, 6, 14), reserva.imported_end_date
  end

  test "updates a manually edited reservation when source dates change" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:changed@example.com
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva = @cabana.reservas.find_by!(ical_uid: "changed@example.com")
    reserva.update!(
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 15),
      manual_override: true
    )

    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:changed@example.com
      DTSTART;VALUE=DATE:20260613
      DTEND;VALUE=DATE:20260615
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva.reload

    assert_equal Date.new(2026, 6, 13), reserva.start_date
    assert_equal Date.new(2026, 6, 15), reserva.end_date
    assert_not reserva.manual_override?
  end

  test "marks a future manually edited reservation missing when it disappears from the feed" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:canceled@example.com
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva = @cabana.reservas.find_by!(ical_uid: "canceled@example.com")
    reserva.update!(
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 15),
      manual_override: true
    )

    result = import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      END:VCALENDAR
    ICS

    assert_equal 1, result.missing
    assert Reserva.exists?(reserva.id)
    assert reserva.reload.ical_missing?
  end

  test "does not mark a past reservation missing when it disappears from the feed" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:past@example.com
      DTSTART;VALUE=DATE:20260610
      DTEND;VALUE=DATE:20260612
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva = @cabana.reservas.find_by!(ical_uid: "past@example.com")

    result = import(<<~ICS, today: Date.new(2026, 6, 15))
      BEGIN:VCALENDAR
      VERSION:2.0
      END:VCALENDAR
    ICS

    assert_equal 0, result.missing
    assert_not reserva.reload.ical_missing?
  end

  test "does not mark event missing when generated uid did not come from the feed" do
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    reserva = @cabana.reservas.find_by!(origem: "airbnb")

    result = import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      END:VCALENDAR
    ICS

    assert_equal 0, result.missing
    assert_not reserva.reload.ical_missing?
  end

  test "clears missing flag when event reappears in the feed" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:reappeared@example.com
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS

    import(ics)
    reserva = @cabana.reservas.find_by!(ical_uid: "reappeared@example.com")
    import(<<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      END:VCALENDAR
    ICS

    assert reserva.reload.ical_missing?

    import(ics)

    assert_not reserva.reload.ical_missing?
  end

  test "adds MG cleaning services for Serra da Mantiqueira cabanas" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    create_cleaning_services(filial)
    create_service("outra limpeza entrada (MG)", filial)
    create_service("lavanderia (MG)", filial)

    IcalReservationImporter.new(
      cabana: cabana,
      platform: "booking",
      url: "unused",
      ics_content: ics_for("mg-cleaning@example.com")
    ).call

    service_names = cabana.reservas.first.services.pluck(:name)

    assert_includes service_names, "➡️ Limpeza Entrada (MG)"
    assert_includes service_names, "⬅️ Limpeza de Saida (MG)"
    assert_not_includes service_names, "outra limpeza entrada (MG)"
    assert_not_includes service_names, "lavanderia (MG)"
    assert_not_includes service_names, "➡️ Limpeza Entrada (SP)"
    assert_not_includes service_names, "⬅️ Limpeza de Saida (SP)"

    reserva = cabana.reservas.first
    entrada = reserva.reserva_services.joins(:service).find_by!(services: { name: "➡️ Limpeza Entrada (MG)" })
    saida = reserva.reserva_services.joins(:service).find_by!(services: { name: "⬅️ Limpeza de Saida (MG)" })

    assert_equal reserva.start_date, entrada.service_date
    assert_equal reserva.end_date, saida.service_date
  end

  test "adds SP cleaning services for Fattoria di Brauna cabanas" do
    filial = Filial.create!(name: "Fattoria di Braúna")
    cabana = Cabana.create!(name: "Cabana SP", price: 100, filial: filial)
    create_cleaning_services(filial)

    IcalReservationImporter.new(
      cabana: cabana,
      platform: "holmy",
      url: "unused",
      ics_content: ics_for("sp-cleaning@example.com")
    ).call

    service_names = cabana.reservas.first.services.pluck(:name)

    assert_includes service_names, "➡️ Limpeza Entrada (SP)"
    assert_includes service_names, "⬅️ Limpeza de Saida (SP)"
    assert_not_includes service_names, "➡️ Limpeza Entrada (MG)"
    assert_not_includes service_names, "⬅️ Limpeza de Saida (MG)"
  end

  test "restores missing required cleaning service while source dates stay the same" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    create_cleaning_services(filial)
    ics = ics_for("manual-service@example.com")

    IcalReservationImporter.new(cabana: cabana, platform: "booking", url: "unused", ics_content: ics).call

    reserva = cabana.reservas.first
    removed_service = Service.all.detect { |service| service.name == "➡️ Limpeza Entrada (MG)" }
    reserva.reserva_services.find_by!(service: removed_service).destroy!

    IcalReservationImporter.new(cabana: cabana, platform: "booking", url: "unused", ics_content: ics).call

    assert_includes reserva.reload.services.pluck(:name), "➡️ Limpeza Entrada (MG)"
  end

  test "restores cleaning services when source dates change" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    create_cleaning_services(filial)

    IcalReservationImporter.new(
      cabana: cabana,
      platform: "booking",
      url: "unused",
      ics_content: ics_for("changed-cleaning@example.com")
    ).call

    reserva = cabana.reservas.first
    removed_service = Service.all.detect { |service| service.name == "➡️ Limpeza Entrada (MG)" }
    reserva.reserva_services.find_by!(service: removed_service).destroy!

    IcalReservationImporter.new(
      cabana: cabana,
      platform: "booking",
      url: "unused",
      ics_content: <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:changed-cleaning@example.com
        DTSTART;VALUE=DATE:20260613
        DTEND;VALUE=DATE:20260615
        SUMMARY:Reserved
        END:VEVENT
        END:VCALENDAR
      ICS
    ).call

    assert_includes reserva.reload.services.pluck(:name), "➡️ Limpeza Entrada (MG)"
  end

  private

  def import(ics, today: Date.new(2026, 5, 31))
    IcalReservationImporter.new(
      cabana: @cabana,
      platform: "airbnb",
      url: "unused",
      ics_content: ics,
      today: today
    ).call
  end

  def create_cleaning_services(filial)
    [
      "➡️ Limpeza Entrada (MG)",
      "⬅️ Limpeza de Saida (MG)",
      "➡️ Limpeza Entrada (SP)",
      "⬅️ Limpeza de Saida (SP)"
    ].each do |name|
      create_service(name, filial)
    end
  end

  def create_service(name, filial)
    user = User.create!(
      email: "services-#{filial.id}-#{name.parameterize}@example.com",
      password: "password",
      password_confirmation: "password",
      name: "Servicos"
    )

    Service.create!(name: name, price: 0, filial: filial, user: user)
  end

  def ics_for(uid)
    <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:#{uid}
      DTSTART;VALUE=DATE:20260612
      DTEND;VALUE=DATE:20260614
      SUMMARY:Reserved
      END:VEVENT
      END:VCALENDAR
    ICS
  end
end
