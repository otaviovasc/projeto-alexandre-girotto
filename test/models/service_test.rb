require "test_helper"

class ServiceTest < ActiveSupport::TestCase
  test "uses guest price for a regular reservation" do
    service = Service.new(price: 120, partner_price: 85)
    reserva = Reserva.new(user: User.new(partner: false))

    assert_equal 120, service.price_for(reserva)
  end

  test "uses partner price for a partner reservation" do
    service = Service.new(price: 120, partner_price: 85)
    reserva = Reserva.new(user: User.new(partner: true))

    assert_equal 85, service.price_for(reserva)
  end

  test "defaults partner price to guest price" do
    service = Service.new(price: 120)

    service.valid?

    assert_equal 120, service.partner_price
  end

  test "groups services into portal categories" do
    assert_equal "Refeições", Service.new(name: "Café da Manhã").portal_category
    assert_equal "Passeios", Service.new(name: "Passeio a Cavalo").portal_category
    assert_equal "Relaxamento", Service.new(name: "Massagem Relaxante").portal_category
    assert_equal "Decorações e surpresas", Service.new(name: "Fotos Impressas (até 3)").portal_category
  end

  test "recognizes printed photos service" do
    assert Service.new(name: "Fotos Impressas (até 3)").photo_print_service?
    assert_not Service.new(name: "Decoração de Pétalas e Luzinhas").photo_print_service?
  end

  test "shows the correct people label in the portal" do
    assert_equal "Para até 2 pessoas", Service.new(name: "Trilha a Pé").portal_people_label
    assert_equal "Para 1 pessoa", Service.new(name: "Massagem para uma pessoa").portal_people_label
    assert_equal "Para 2 pessoas", Service.new(name: "Massagem para duas pessoas").portal_people_label
    assert_nil Service.new(name: "Espumante").portal_people_label
    assert_nil Service.new(name: "Fotos Impressas (até 3)").portal_people_label
    assert_nil Service.new(name: "Decoração de Pétalas e Luzinhas").portal_people_label
  end
end
