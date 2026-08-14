require "test_helper"

class CartItemTest < ActiveSupport::TestCase
  test "visible observation hides automatic notes and keeps guest notes" do
    cart_item = cart_items(:one)
    cart_item.observation = "de tarde após check-in. Sem lactose"

    assert_equal "Sem lactose", cart_item.visible_observation
  end
end
