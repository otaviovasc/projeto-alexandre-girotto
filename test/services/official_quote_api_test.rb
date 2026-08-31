require "test_helper"

class OfficialQuoteApiTest < ActiveSupport::TestCase
  setup do
    @filial = Filial.create!(name: "Fattoria di Brauna", region: "SP")
    @cabana = Cabana.create!(name: "Zucchero - Fattoria di Brauna", filial: @filial, price: 799)
    @user = create_user("official-quote-api-#{SecureRandom.hex(4)}@example.com")
    @service = Service.create!(
      name: "Jantar (SP)",
      description: "Jantar para duas pessoas.",
      price: 109,
      partner_price: 95,
      filial: @filial,
      user: @user,
      show_in_marketplace: true
    )
  end

  test "returns quote with render services and google sheets price source" do
    payload = OfficialQuoteApi.new(
      params: { destino: "brauna", checkin: "2035-09-10", checkout: "2035-09-12" },
      pricing: FakePricing.new
    ).call

    assert_equal true, payload[:ok]
    assert_equal "Google Sheets", payload.dig(:fontes, :precos)
    assert_equal "Render", payload.dig(:fontes, :disponibilidade)
    assert_equal "Render", payload.dig(:fontes, :servicos)

    cabin = payload[:cabanas].find { |row| row[:id] == @cabana.id }
    assert_not_nil cabin
    assert_equal 1000.0, cabin[:hospedagem]
    assert_equal [@service.id], cabin[:servicos].map { |service| service[:id] }
    assert_equal 109.0, cabin[:servicos].first[:preco]
  end

  test "marks cabin unavailable when render availability blocks the range" do
    guest = create_user("official-quote-block-#{SecureRandom.hex(4)}@example.com")
    Reserva.create!(
      cabana: @cabana,
      user: guest,
      start_date: Date.new(2035, 9, 10),
      end_date: Date.new(2035, 9, 12),
      payment_status: "paid",
      blocks_availability: true,
      total_price: 1000
    )

    payload = OfficialQuoteApi.new(
      params: { cabana_id: @cabana.id, checkin: "2035-09-10", checkout: "2035-09-12" },
      pricing: FakePricing.new
    ).call

    assert_equal false, payload[:cabanas].first[:disponivel]
    assert_includes payload[:cabanas].first[:motivos], "Cabana ocupada nesse período."
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

  class FakePricing
    def quote(cabana:, start_date:, end_date:)
      {
        nights: [
          { date: start_date, price: 500.to_d, weekend: false, holiday: false, season: "Baixa Temporada" },
          { date: start_date + 1.day, price: 500.to_d, weekend: false, holiday: false, season: "Baixa Temporada" }
        ],
        nights_count: (end_date - start_date).to_i,
        stay_total: 1000.to_d,
        minimum: 1,
        meets_minimum: true,
        minimum_message: nil
      }
    end
  end
end
