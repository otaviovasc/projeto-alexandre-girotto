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
end
