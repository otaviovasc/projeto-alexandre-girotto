require "test_helper"

class ReservationWhatsappTaskMaterializerTest < ActiveSupport::TestCase
  setup do
    EmailAutomationSetting.delete_all
    ReservationWhatsappTask.delete_all
    OperationalServiceOccurrence.delete_all
    RecurringMaintenanceRule.delete_all
    ReservationEmailTemplate.delete_all

    EmailAutomationSetting.create!(enabled: true, activated_at: 1.year.ago)
    @serra = Filial.create!(name: "Serra da Mantiqueira")
    @brauna = Filial.create!(name: "Fattoria di Brauna")
    @user = User.create!(
      name: "Maria Silva",
      email: "maria-materializer@example.com",
      telephone: "11999999999"
    )
    @cabana_serra = Cabana.create!(name: "Valle - Serra da Mantiqueira", filial: @serra, price: 100)
    @cabana_brauna = Cabana.create!(name: "Zucchero - Fattoria di Brauna", filial: @brauna, price: 100)
  end

  test "creates grouped Bruna timing task for Serra services" do
    reserva = create_reserva(@cabana_serra)
    create_reserva_service(reserva, "Passeio a Cavalo", reserva.start_date + 1.day)
    create_reserva_service(reserva, "Trilha", reserva.start_date + 2.days)

    ReservationWhatsappTaskMaterializer.run(date: reserva.start_date - 5.days)

    task = ReservationWhatsappTask.find_by!(
      reserva: reserva,
      trigger_key: ReservationWhatsappTaskMaterializer::SERVICE_BRUNA_TRIGGER_KEY
    )

    assert_nil task.reservation_email_template
    assert_equal "Horários com Bruna", task.template_name
    assert_match "Oi Bruna", task.message_body
    assert_match "O passeio a cavalo dia", task.message_body
    assert_match "A trilha dia", task.message_body
    assert_match "código de reserva ##{reserva.id}", task.message_body
    assert_equal reserva.start_date - 5.days, task.scheduled_on
  end

  test "does not create Bruna timing task for Brauna services" do
    reserva = create_reserva(@cabana_brauna)
    create_reserva_service(reserva, "Passeio a Cavalo", reserva.start_date + 1.day)

    ReservationWhatsappTaskMaterializer.run(date: reserva.start_date - 5.days)

    assert_nil ReservationWhatsappTask.find_by(
      reserva: reserva,
      trigger_key: ReservationWhatsappTaskMaterializer::SERVICE_BRUNA_TRIGGER_KEY
    )
  end

  test "creates photo task for guest and removes it when service is canceled" do
    reserva = create_reserva(@cabana_serra)
    reserva_service = create_reserva_service(reserva, "Fotos Impressas", reserva.start_date)

    ReservationWhatsappTaskMaterializer.run(date: reserva.start_date - 5.days)

    task = ReservationWhatsappTask.find_by!(
      reserva: reserva,
      trigger_key: ReservationWhatsappTaskMaterializer::SERVICE_PHOTOS_TRIGGER_KEY
    )
    assert_equal "Fotos para impressão", task.template_name
    assert_match "Oi Maria Silva", task.message_body
    assert_match "envie 3 fotos", task.message_body

    reserva_service.update!(status: "cancelled")
    ReservationWhatsappTaskMaterializer.run(date: reserva.start_date - 5.days)

    assert_nil ReservationWhatsappTask.find_by(
      reserva: reserva,
      trigger_key: ReservationWhatsappTaskMaterializer::SERVICE_PHOTOS_TRIGGER_KEY
    )
  end

  test "creates whatsapp task for recurring maintenance" do
    rule = RecurringMaintenanceRule.create!(
      title: "Olhar estrada",
      message_body: "Oi {{nome}}, olhar {{titulo}} na {{cabana}} dia {{data_curta}}.",
      recipients_text: "Bruna | 35999999999",
      frequency_interval: 1,
      frequency_unit: "monthly",
      first_due_on: Date.current + 2.days,
      cabana_ids: [@cabana_serra.id]
    )

    ReservationWhatsappTaskMaterializer.run(date: Date.current + 1.day)

    occurrence = OperationalServiceOccurrence.find_by!(
      kind: "recurring_maintenance",
      stable_id: "recurring-maintenance-rule-#{rule.id}-cabana-#{@cabana_serra.id}-#{(Date.current + 2.days).iso8601}"
    )
    task = ReservationWhatsappTask.find_by!(operational_service_occurrence: occurrence)

    assert_nil task.reserva
    assert_equal "Manutenção: Olhar estrada", task.template_name
    assert_equal "Manutenção", task.reservation_label
    assert_equal "Bruna", task.guest_name
    assert_equal "35999999999", task.guest_phone
    assert_equal Date.current + 1.day, task.scheduled_on
    assert_match "olhar Olhar estrada", task.message_body
  end

  private

  def create_reserva(cabana)
    Reserva.create!(
      cabana: cabana,
      user: @user,
      start_date: Date.current + 10.days,
      end_date: Date.current + 12.days,
      total_price: 200,
      payment_status: "paid",
      blocks_availability: true,
      group_created: true
    )
  end

  def create_reserva_service(reserva, name, service_date)
    service = Service.create!(
      name: name,
      description: name,
      price: 10,
      partner_price: 10,
      duration: "1h",
      filial: reserva.cabana.filial,
      user: @user
    )

    ReservaService.create!(
      reserva: reserva,
      service: service,
      quantity: 1,
      service_date: service_date,
      status: "active"
    )
  end
end
