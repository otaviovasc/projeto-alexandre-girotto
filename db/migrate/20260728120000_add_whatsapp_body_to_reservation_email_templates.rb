class AddWhatsappBodyToReservationEmailTemplates < ActiveRecord::Migration[7.0]
  WHATSAPP_BODIES = {
    'reservation_confirmed' => <<~BODY,
      Olá, {{hospede}}.

      Sua reserva no Villaggio Girotto foi confirmada.

      Cabana: {{cabana}}
      Entrada: {{entrada}}
      Saída: {{saida}}

      Em breve enviamos as informações da hospedagem por aqui.
    BODY
    'fnrh_7_days' => <<~BODY,
      Olá, {{hospede}}! Falta 7 dias para sua estadia no Villaggio.

      Lembre de preencher o pré-check-in/FNRH e acessar o material do hóspede, que fica na primeira mensagem deste grupo.
    BODY
    'fnrh_4_days' => <<~BODY,
      Olá, {{hospede}}! Sua estadia está chegando.

      Confira no material do hóspede o horário de chegada e as instruções de acesso.

      Para chegar, use o Google Maps e siga as orientações do material do hóspede.
    BODY
    'arrival_2_days' => <<~BODY,
      Olá, {{hospede}}! Sua estadia está chegando.

      Separe suas malas, itens pessoais, condimentos que desejar utilizar e cobertor extra caso costume sentir frio.

      Antes da viagem, confira o material do hóspede na primeira mensagem deste grupo.
    BODY
    'checkin_day_7am' => <<~BODY,
      Olá, {{hospede}}! Hoje é o dia da sua chegada ao Villaggio.

      Confira o horário combinado aqui no grupo e baixe o material do hóspede.

      Carregue a rota APENAS pelo Google Maps e siga as instruções do material.

      Não temos portaria fixa e não há equipe no local após o horário de chegada. Se não se sentir confortável com a última parte do trajeto, pare no estacionamento da entrada.
    BODY
    'first_night_check' => <<~BODY,
      Olá, {{hospede}}! Passando para saber se está tudo certo com sua estadia.
    BODY
    'checkout_18h' => <<~BODY,
      Olá, {{hospede}}! Esperamos que tenha dado tudo certo na sua estadia.

      Se tiver qualquer ponto a destacar, pode enviar por aqui.
    BODY
    'services_15_days' => <<~BODY,
      Olá, {{hospede}}! Ainda dá tempo de adicionar serviços à sua estadia, como refeições, experiências e itens especiais.

      As opções ficam no material do hóspede, na primeira mensagem deste grupo.
    BODY
    'services_12_days' => <<~BODY,
      Olá, {{hospede}}! Estamos nos aproximando do prazo final para adicionar serviços à sua estadia.

      Confira as opções no material do hóspede, na primeira mensagem deste grupo.
    BODY
    'services_last_day' => <<~BODY
      Olá, {{hospede}}! Hoje é o último dia para adicionar serviços à sua estadia pelo sistema.

      Depois do prazo, não garantimos a possibilidade de compra de serviços. Não deixe para a última hora e garanta ainda hoje os serviços que deseja incluir na sua experiência.
    BODY
  }.freeze

  def up
    add_column :reservation_email_templates, :whatsapp_body, :text unless column_exists?(:reservation_email_templates, :whatsapp_body)

    template_model.reset_column_information
    template_model.find_each do |template|
      whatsapp_body = WHATSAPP_BODIES[template.trigger_key].presence || template.body
      next if template.whatsapp_body.present?

      template.update_columns(whatsapp_body: whatsapp_body, updated_at: Time.current)
    end

    change_column_null :reservation_email_templates, :whatsapp_body, false
  end

  def down
    remove_column :reservation_email_templates, :whatsapp_body if column_exists?(:reservation_email_templates, :whatsapp_body)
  end

  private

  def template_model
    @template_model ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'reservation_email_templates'
    end
  end
end
