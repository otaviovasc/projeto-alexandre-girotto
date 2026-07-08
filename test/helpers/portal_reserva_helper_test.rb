require "test_helper"

class PortalReservaHelperTest < ActionView::TestCase
  test "shows the weekly menu only for meals in Minas Gerais" do
    mg_filial = Filial.new(name: "Serra da Mantiqueira")
    sp_filial = Filial.new(name: "Fattoria di Brauna")

    mg_lunch = Service.new(name: "Almoço", filial: mg_filial)
    sp_lunch = Service.new(name: "Almoço", filial: sp_filial)
    reserva = Reserva.new(start_date: Date.new(2026, 7, 14), end_date: Date.new(2026, 7, 16))

    menu = portal_service_menu(mg_lunch, reserva)

    assert_equal 3, menu.size
    assert_equal "Terça-feira, 14/07", menu.first.first
    assert_equal "Truta, arroz, salada e pão", menu.first.last
    assert_nil portal_service_menu(sp_lunch, reserva)
  end
end
