require "test_helper"

class CleaningServicesAssignerTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 1, 1, 12)
  end

  teardown do
    travel_back
  end

  test "adds required cleaning services when a reservation is created" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    user = create_user("guest@example.com")
    create_cleaning_services(filial)

    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )

    service_names = reserva.services.pluck(:name)
    entrada = reserva.reserva_services.joins(:service).find_by!(services: { name: "➡️ Limpeza Entrada (MG)" })
    saida = reserva.reserva_services.joins(:service).find_by!(services: { name: "⬅️ Limpeza de Saida (MG)" })

    assert_includes service_names, "➡️ Limpeza Entrada (MG)"
    assert_includes service_names, "⬅️ Limpeza de Saida (MG)"
    assert_equal reserva.start_date, entrada.service_date
    assert_equal reserva.end_date, saida.service_date
    assert_not entrada.manual_date_override?
    assert_not saida.manual_date_override?
  end

  test "adds missing pair when only one cleaning service is added" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    user = create_user("guest-pair@example.com")
    create_cleaning_services(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )
    reserva.reserva_services.destroy_all

    saida = Service.find_by!(name: "⬅️ Limpeza de Saida (MG)")
    ReservaService.create!(reserva: reserva, service: saida, quantity: 1, service_date: reserva.end_date)

    service_names = reserva.reload.services.pluck(:name)

    assert_includes service_names, "➡️ Limpeza Entrada (MG)"
    assert_includes service_names, "⬅️ Limpeza de Saida (MG)"
  end

  test "updates cleaning service dates when reservation dates change" do
    filial = Filial.create!(name: "Fattoria di Braúna")
    cabana = Cabana.create!(name: "Cabana SP", price: 100, filial: filial)
    user = create_user("guest-date@example.com")
    create_cleaning_services(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )

    reserva.update!(start_date: Date.new(2026, 6, 13), end_date: Date.new(2026, 6, 15))

    entrada = reserva.reserva_services.joins(:service).find_by!(services: { name: "➡️ Limpeza Entrada (SP)" })
    saida = reserva.reserva_services.joins(:service).find_by!(services: { name: "⬅️ Limpeza de Saida (SP)" })

    assert_equal Date.new(2026, 6, 13), entrada.service_date
    assert_equal Date.new(2026, 6, 15), saida.service_date
    assert_not entrada.manual_date_override?
    assert_not saida.manual_date_override?
  end

  test "keeps manually changed cleaning service date until reservation dates change" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    user = create_user("guest-manual-date@example.com")
    create_cleaning_services(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )
    entrada = reserva.reserva_services.joins(:service).find_by!(services: { name: "➡️ Limpeza Entrada (MG)" })

    entrada.update!(service_date: Date.new(2026, 6, 11))
    CleaningServicesAssigner.new(reserva.reload).call

    assert_equal Date.new(2026, 6, 11), entrada.reload.service_date
    assert entrada.manual_date_override?

    reserva.update!(start_date: Date.new(2026, 6, 13), end_date: Date.new(2026, 6, 15))

    assert_equal Date.new(2026, 6, 13), entrada.reload.service_date
    assert_not entrada.manual_date_override?
  end

  test "keeps the manual date when one cleaning service is added and completes the pair" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana MG", price: 100, filial: filial)
    user = create_user("guest-manual-pair@example.com")
    create_cleaning_services(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 6, 12),
      end_date: Date.new(2026, 6, 14),
      payment_status: "paid",
      total_price: 0
    )
    reserva.reserva_services.destroy_all

    saida = Service.find_by!(name: "⬅️ Limpeza de Saida (MG)")
    ReservaService.create!(
      reserva: reserva,
      service: saida,
      quantity: 1,
      service_date: Date.new(2026, 6, 15)
    )

    entrada_service = reserva.reload.reserva_services.joins(:service).find_by!(services: { name: "➡️ Limpeza Entrada (MG)" })
    saida_service = reserva.reserva_services.joins(:service).find_by!(services: { name: "⬅️ Limpeza de Saida (MG)" })

    assert_equal Date.new(2026, 6, 12), entrada_service.service_date
    assert_not entrada_service.manual_date_override?
    assert_equal Date.new(2026, 6, 15), saida_service.service_date
    assert saida_service.manual_date_override?
  end

  test "moves cleaning services outside the official stay for early check in and late checkout" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana operacional", price: 100, filial: filial)
    user = create_user("guest-operational@example.com")
    create_cleaning_services(filial)

    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 8, 10),
      end_date: Date.new(2026, 8, 12),
      early_checkin: true,
      late_checkout: true,
      payment_status: "paid",
      total_price: 0
    )

    entrada = reserva.reserva_services.joins(:service).find_by!(services: { name: "➡️ Limpeza Entrada (MG)" })
    saida = reserva.reserva_services.joins(:service).find_by!(services: { name: "⬅️ Limpeza de Saida (MG)" })

    assert_equal Date.new(2026, 8, 9), entrada.service_date
    assert_equal CleaningServicesAssigner::EARLY_CHECKIN_NOTE, entrada.observation
    assert_equal Date.new(2026, 8, 13), saida.service_date
    assert_equal CleaningServicesAssigner::LATE_CHECKOUT_NOTE, saida.observation
  end

  test "removes automatic operational notes when the options are disabled" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    cabana = Cabana.create!(name: "Cabana sem extensão", price: 100, filial: filial)
    user = create_user("guest-remove-note@example.com")
    create_cleaning_services(filial)
    reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.new(2026, 9, 10),
      end_date: Date.new(2026, 9, 12),
      early_checkin: true,
      late_checkout: true,
      payment_status: "paid",
      total_price: 0
    )

    reserva.update!(early_checkin: false, late_checkout: false)
    entrada = reserva.reserva_services.joins(:service).find_by!(services: { name: "➡️ Limpeza Entrada (MG)" })
    saida = reserva.reserva_services.joins(:service).find_by!(services: { name: "⬅️ Limpeza de Saida (MG)" })

    assert_equal reserva.start_date, entrada.service_date
    assert_nil entrada.observation
    assert_equal reserva.end_date, saida.service_date
    assert_nil saida.observation
  end

  test "replaces cleaning services when reservation changes region" do
    mg_filial = Filial.create!(name: "Serra da Mantiqueira")
    sp_filial = Filial.create!(name: "Fattoria di Braúna")
    mg_cabana = Cabana.create!(name: "Cabana MG troca", price: 100, filial: mg_filial)
    sp_cabana = Cabana.create!(name: "Cabana SP troca", price: 100, filial: sp_filial)
    user = create_user("guest-change-region@example.com")

    [
      ["➡️ Limpeza Entrada (MG)", mg_filial],
      ["⬅️ Limpeza de Saida (MG)", mg_filial],
      ["➡️ Limpeza Entrada (SP)", sp_filial],
      ["⬅️ Limpeza de Saida (SP)", sp_filial]
    ].each do |name, filial|
      Service.create!(
        name: name,
        price: 0,
        filial: filial,
        user: create_user("#{name.parameterize}-change-region@example.com")
      )
    end

    reserva = Reserva.create!(
      cabana: mg_cabana,
      user: user,
      start_date: Date.new(2026, 10, 10),
      end_date: Date.new(2026, 10, 12),
      payment_status: "paid",
      total_price: 0
    )

    reserva.update!(cabana: sp_cabana)

    service_names = reserva.reload.services.pluck(:name)
    assert_includes service_names, "➡️ Limpeza Entrada (SP)"
    assert_includes service_names, "⬅️ Limpeza de Saida (SP)"
    assert_not_includes service_names, "➡️ Limpeza Entrada (MG)"
    assert_not_includes service_names, "⬅️ Limpeza de Saida (MG)"
  end

  private

  def create_cleaning_services(filial)
    [
      "➡️ Limpeza Entrada (MG)",
      "⬅️ Limpeza de Saida (MG)",
      "➡️ Limpeza Entrada (SP)",
      "⬅️ Limpeza de Saida (SP)"
    ].each do |name|
      Service.create!(name: name, price: 0, filial: filial, user: create_user("#{name.parameterize}-#{filial.id}@example.com"))
    end
  end

  def create_user(email)
    User.create!(
      email: email,
      password: "password",
      password_confirmation: "password",
      name: "Teste"
    )
  end
end
