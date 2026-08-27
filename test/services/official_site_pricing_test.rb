require "test_helper"

class OfficialSitePricingTest < ActiveSupport::TestCase
  setup do
    @filial = Filial.create!(name: "Fattoria di Brauna")
    @cabana = Cabana.create!(name: "Vecchio Toro", filial: @filial, price: 100)
    @pricing = OfficialSitePricing.new
  end

  test "uses official sheet alta weekend prices" do
    @pricing.stub(:data, fake_sheet_data) do
      quote = @pricing.quote(
        cabana: @cabana,
        start_date: Date.new(2026, 7, 10),
        end_date: Date.new(2026, 7, 12)
      )

      assert_equal 2, quote[:nights_count]
      assert_equal 1926.to_d, quote[:stay_total]
    end
  end

  test "uses holiday pricing window for tuesday holidays" do
    data = fake_sheet_data(
      feriados: [{
        nome: "Feriado de terca",
        inicio: Date.new(2026, 9, 8),
        fim: Date.new(2026, 9, 8),
        acrescimo: 0.25.to_d,
        ativo: true,
        minimo_diarias: 2
      }]
    )

    @pricing.stub(:data, data) do
      quote = @pricing.quote(
        cabana: @cabana,
        start_date: Date.new(2026, 9, 4),
        end_date: Date.new(2026, 9, 5)
      )

      assert_equal 999.to_d, quote[:stay_total]
      assert quote[:nights].first[:holiday]
      assert_equal "Feriado de terca", quote[:nights].first[:holiday_name]
    end
  end

  test "allows one friday night only when saturday night is blocked" do
    @pricing.stub(:data, fake_sheet_data) do
      open_weekend_quote = @pricing.quote(
        cabana: @cabana,
        start_date: Date.new(2026, 9, 4),
        end_date: Date.new(2026, 9, 5)
      )

      assert_equal 2, open_weekend_quote[:minimum]
      assert_not open_weekend_quote[:meets_minimum]

      Reserva.create!(
        cabana: @cabana,
        user: users(:one),
        start_date: Date.new(2026, 9, 5),
        end_date: Date.new(2026, 9, 7),
        payment_status: "paid",
        blocks_availability: true,
        total_price: 0
      )

      gap_quote = @pricing.quote(
        cabana: @cabana,
        start_date: Date.new(2026, 9, 4),
        end_date: Date.new(2026, 9, 5)
      )

      assert_equal 1, gap_quote[:minimum]
      assert gap_quote[:meets_minimum]
    end
  end

  private

  def fake_sheet_data(feriados: [])
    {
      cabanas: [{
        cabana: "Vecchio Toro",
        filial: "Fattoria di Brauna",
        baixa_semana: 627.to_d,
        baixa_fim_de_semana: 795.to_d,
        ativa: true
      }],
      precos: [{
        cabana: "Vecchio Toro",
        filial: "Fattoria di Brauna",
        baixa_semana: 627.to_d,
        baixa_fds: 795.to_d,
        media_semana: 690.to_d,
        media_fds: 875.to_d,
        alta_semana: 759.to_d,
        alta_fds: 963.to_d,
        feriado_baixa_semana: 784.to_d,
        feriado_baixa_fds: 994.to_d,
        feriado_media_semana: 888.to_d,
        feriado_media_fds: 999.to_d,
        feriado_alta_semana: 949.to_d,
        feriado_alta_fds: 1204.to_d
      }],
      feriados: feriados,
      servicos: []
    }
  end
end
