require "test_helper"

class OfficialServicesCatalogTest < ActiveSupport::TestCase
  setup do
    @serra = Filial.create!(name: "Serra da Mantiqueira", region: "MG")
    @brauna = Filial.create!(name: "Fattoria di Brauna", region: "SP")
    @user = create_user("official-services-catalog-#{SecureRandom.hex(4)}@example.com")
  end

  test "groups public services by destination using render prices" do
    Service.create!(name: "Cafe da manha (MG)", price: 112, partner_price: 90, filial: @serra, user: @user, show_in_marketplace: true)
    Service.create!(name: "Cafe da manha (SP)", price: 129, partner_price: 98, filial: @brauna, user: @user, show_in_marketplace: true)
    Service.create!(name: "Enviar Avaliacao (SP)", price: 0, partner_price: 0, filial: @brauna, user: @user, show_in_marketplace: true)

    catalog = OfficialServicesCatalog.new.all
    breakfast = catalog.find { |service| service[:servico] == "Cafe da manha" }

    assert_equal true, breakfast[:disponivel_serra]
    assert_equal true, breakfast[:disponivel_brauna]
    assert_equal 112.0, breakfast[:preco_serra]
    assert_equal 129.0, breakfast[:preco_brauna]
    refute catalog.any? { |service| service[:servico].to_s.match?(/avaliacao/i) }
  end

  test "returns only services for selected filial" do
    serra_service = Service.create!(name: "Almoco (MG)", price: 91, partner_price: 80, filial: @serra, user: @user, show_in_marketplace: true)
    Service.create!(name: "Almoco (SP)", price: 109, partner_price: 95, filial: @brauna, user: @user, show_in_marketplace: true)

    rows = OfficialServicesCatalog.new.for_filial(@serra)

    assert_equal [serra_service.id], rows.map { |row| row[:id] }
    assert_equal 91.0, rows.first[:preco]
  end

  private

  def create_user(email)
    User.create!(
      name: email.split("@").first,
      email: email,
      password: "password123",
      password_confirmation: "password123",
      telephone: SecureRandom.random_number(10**11).to_s.rjust(11, "0")
    )
  end
end
