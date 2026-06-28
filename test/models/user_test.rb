require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "matches reservation name without requiring accents" do
    user = User.new(name: "Rômulo de Souza", email: "romulo@example.com")

    assert user.matches_reservation_identifier?("Romulo")
    assert user.matches_reservation_identifier?("ROMULO DE SOUZA")
  end

  test "does not match a different reservation name" do
    user = User.new(name: "Rômulo de Souza", email: "romulo@example.com")

    assert_not user.matches_reservation_identifier?("Roberto")
  end
end
