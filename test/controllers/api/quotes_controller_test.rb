require "test_helper"

class Api::QuotesControllerTest < ActionDispatch::IntegrationTest
  test "returns lightweight quote payload for a destination" do
    filial = Filial.create!(name: "Fattoria di Brauna")
    Cabana.create!(name: "Zucchero", filial: filial, price: 100)

    fake_pricing = FakePricing.new(available: true)

    OfficialSitePricing.stub(:new, fake_pricing) do
      get "/api/cotacao", params: {
        destino: "brauna",
        checkin: "2027-09-03",
        checkout: "2027-09-05"
      }
    end

    assert_response :success
    payload = response.parsed_body

    assert_equal true, payload.fetch("ok")
    assert_equal "Fattoria di Brauna", payload.fetch("destino")
    assert_equal 2, payload.fetch("noites")
    assert_equal "Google Sheets", payload.dig("fontes", "precos")

    cabin = payload.fetch("cabanas").first
    assert_equal "Zucchero", cabin.fetch("nome")
    assert_equal true, cabin.fetch("disponivel")
    assert_equal 2000.0, cabin.fetch("hospedagem")
    assert_not cabin.key?("diarias")
  end

  test "can include daily details when requested" do
    filial = Filial.create!(name: "Serra da Mantiqueira")
    Cabana.create!(name: "Collina", filial: filial, price: 100)

    fake_pricing = FakePricing.new(available: true)

    OfficialSitePricing.stub(:new, fake_pricing) do
      get "/api/cotacao", params: {
        destino: "serra",
        checkin: "2027-09-03",
        checkout: "2027-09-05",
        detalhes: "1"
      }
    end

    assert_response :success
    cabin = response.parsed_body.fetch("cabanas").first

    assert_equal 2, cabin.fetch("diarias").size
    assert_equal "fim_de_semana", cabin.fetch("diarias").first.fetch("tipo")
  end

  FakePricing = Struct.new(:available, keyword_init: true) do
    def quote(cabana:, start_date:, end_date:)
      {
        nights: [
          {
            date: start_date,
            price: 1000.to_d,
            weekend: true,
            holiday: false,
            holiday_name: nil,
            holiday_date: nil,
            season: "Media Temporada"
          },
          {
            date: start_date + 1.day,
            price: 1000.to_d,
            weekend: true,
            holiday: false,
            holiday_name: nil,
            holiday_date: nil,
            season: "Media Temporada"
          }
        ],
        nights_count: (end_date - start_date).to_i,
        stay_total: 2000.to_d,
        minimum: 2,
        meets_minimum: true,
        minimum_message: ""
      }
    end

    def available?(cabana:, start_date:, end_date:)
      available
    end
  end
end
