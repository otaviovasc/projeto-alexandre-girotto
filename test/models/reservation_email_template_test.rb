require "test_helper"

class ReservationEmailTemplateTest < ActiveSupport::TestCase
  test "fnrh copy is shown only when precheckin is open" do
    template = ReservationEmailTemplate.new(
      trigger_key: "fnrh_7_days",
      name: "FNRH e material - 7 dias antes",
      subject: "FNRH e material",
      body: "Lembre-se de preencher o pré-check-in/FNRH e acessar o material do hóspede.",
      whatsapp_body: "Lembre de preencher o pré-check-in/FNRH e acessar o material do hóspede."
    )
    open_reserva = build_reserva(fnrh_status: "awaiting_precheckin", fnrh_precheckin_url: "https://fnrh.example/precheckin")
    released_reserva = build_reserva(fnrh_status: "precheckin_completed", fnrh_precheckin_url: "https://fnrh.example/precheckin")

    assert_match "pré-check-in/FNRH", template.render_body(open_reserva)
    assert_match "pré-check-in/FNRH", template.render_whatsapp_body(open_reserva)
    assert_equal "FNRH e material - 7 dias antes", template.display_name_for(open_reserva)

    assert_no_match(/FNRH|pré-check-in/i, template.render_body(released_reserva))
    assert_no_match(/FNRH|pré-check-in/i, template.render_whatsapp_body(released_reserva))
    assert_equal "Material do hóspede - 7 dias antes", template.display_name_for(released_reserva)
  end

  private

  def build_reserva(fnrh_status:, fnrh_precheckin_url:)
    filial = Filial.new(name: "Serra da Mantiqueira")
    cabana = Cabana.new(name: "Valle - Serra da Mantiqueira", filial: filial)
    user = User.new(name: "Maria", email: "maria@example.com")

    Reserva.new(
      cabana: cabana,
      user: user,
      start_date: Date.current + 7.days,
      end_date: Date.current + 9.days,
      payment_status: "paid",
      blocks_availability: true,
      group_created: true,
      fnrh_status: fnrh_status,
      fnrh_precheckin_url: fnrh_precheckin_url
    )
  end
end
