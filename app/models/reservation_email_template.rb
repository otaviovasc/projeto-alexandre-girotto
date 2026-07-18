class ReservationEmailTemplate < ApplicationRecord
  has_many :reservation_email_deliveries, dependent: :nullify

  before_validation :assign_custom_trigger_key, on: :create
  before_destroy :cancel_pending_deliveries

  FILIAL_SCOPES = {
    'all' => 'Serra e Braúna',
    'serra' => 'Serra da Mantiqueira',
    'brauna' => 'Fattoria di Braúna'
  }.freeze

  TRIGGER_ANCHORS = {
    'reservation_confirmed' => 'Quando a reserva for confirmada',
    'checkin' => 'Relativo ao check-in',
    'checkout' => 'Relativo ao checkout',
    'service_deadline' => 'Relativo ao último dia de compra de serviços',
    'first_night' => 'Manhã após a primeira diária'
  }.freeze

  DEFAULTS = [
    {
      trigger_key: 'reservation_confirmed',
      name: 'Reserva confirmada',
      trigger_anchor: 'reservation_confirmed',
      offset_days: 0,
      send_time: '09:00',
      filial_scope: 'all',
      subject: 'Reserva confirmada - {{cabana}} | Villaggio Girotto',
      body: <<~BODY
        Olá, {{hospede}}.

        Sua reserva no Villaggio Girotto foi confirmada.

        Código da reserva: {{codigo}}
        Cabana: {{cabana}}
        Entrada: {{entrada}}
        Saída: {{saida}}

        Em breve você receberá as informações da hospedagem no grupo de estadia no WhatsApp.

        Caso não receba nenhuma mensagem em até 48h, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'fnrh_7_days',
      name: 'FNRH e material - 7 dias antes',
      trigger_anchor: 'checkin',
      offset_days: -7,
      send_time: '09:00',
      filial_scope: 'all',
      subject: 'Faltam 7 dias para sua estadia na {{cabana}} | Villaggio Girotto',
      body: <<~BODY
        Olá, {{hospede}}.

        Faltam 7 dias para sua estadia na {{cabana}}.

        Lembre-se de preencher o pré-check-in/FNRH e acessar o material do hóspede, que fica na primeira mensagem do grupo de estadia no WhatsApp.

        Código da reserva: {{codigo}}

        Qualquer dúvida, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'fnrh_4_days',
      name: 'FNRH e chegada - 4 dias antes',
      trigger_anchor: 'checkin',
      offset_days: -4,
      send_time: '09:00',
      filial_scope: 'all',
      subject: 'Informações importantes para sua chegada na {{cabana}}',
      body: <<~BODY
        Olá, {{hospede}}.

        Sua estadia está chegando. Confira o material do hóspede, o horário de chegada e as instruções de acesso.

        Essas informações estão no grupo de estadia no WhatsApp, principalmente na primeira mensagem.

        Para chegar, use o Google Maps e siga as instruções do material do hóspede.

        Código da reserva: {{codigo}}

        Qualquer dúvida, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'arrival_2_days',
      name: 'Está chegando - 2 dias antes',
      trigger_anchor: 'checkin',
      offset_days: -2,
      send_time: '09:00',
      filial_scope: 'all',
      subject: 'Está chegando sua estadia na {{cabana}}',
      body: <<~BODY
        Olá, {{hospede}}.

        Sua estadia está chegando. Separe suas malas, itens pessoais, condimentos que desejar utilizar e cobertor extra caso costume sentir frio.

        Confira também o material do hóspede antes da viagem. Ele fica na primeira mensagem do grupo de estadia no WhatsApp.

        Código da reserva: {{codigo}}

        Qualquer dúvida, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'checkin_day_7am',
      name: 'Dia da chegada - 7h',
      trigger_anchor: 'checkin',
      offset_days: 0,
      send_time: '07:00',
      filial_scope: 'all',
      subject: 'Hoje é o dia da sua chegada na {{cabana}}',
      body: <<~BODY
        Olá, {{hospede}}.

        Hoje é o dia da sua chegada ao Villaggio.

        Confira o horário combinado no grupo de estadia e baixe o material do hóspede.

        Carregue a rota APENAS pelo Google Maps e siga as instruções do material do hóspede.

        Não temos portaria fixa e não há equipe no local após o horário de chegada. Se não se sentir confortável com a última parte do trajeto, pare no estacionamento da entrada.

        Código da reserva: {{codigo}}

        Qualquer dúvida, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'first_night_check',
      name: 'Checagem da estadia',
      trigger_anchor: 'first_night',
      offset_days: 0,
      send_time: '10:00',
      filial_scope: 'all',
      subject: 'Como está sua estadia na {{cabana}}?',
      body: <<~BODY
        Olá, {{hospede}}.

        Passando para saber se está tudo certo com sua estadia.

        Se precisar de qualquer coisa, fale com a equipe pelo grupo de estadia no WhatsApp ou pelo número: {{whatsapp}}.

        Código da reserva: {{codigo}}

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'checkout_18h',
      name: 'Pós-checkout - 18h',
      trigger_anchor: 'checkout',
      offset_days: 0,
      send_time: '18:00',
      filial_scope: 'all',
      subject: 'Como foi sua estadia na {{cabana}}?',
      body: <<~BODY
        Olá, {{hospede}}.

        Esperamos que tenha dado tudo certo na sua estadia.

        Se tiver qualquer ponto a destacar, fale conosco pelo grupo de estadia ou pelo WhatsApp: {{whatsapp}}.

        Código da reserva: {{codigo}}

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'services_15_days',
      name: 'Serviços extras - 15 dias antes',
      trigger_anchor: 'checkin',
      offset_days: -15,
      send_time: '09:00',
      filial_scope: 'all',
      subject: 'Ainda dá tempo de adicionar serviços à sua estadia na {{cabana}}',
      body: <<~BODY
        Olá, {{hospede}}.

        Ainda dá tempo de adicionar serviços à sua estadia, como refeições, experiências e itens especiais.

        Acesse o material do hóspede, que fica na primeira mensagem do grupo de estadia, para conferir as opções disponíveis.

        Código da reserva: {{codigo}}

        Qualquer dúvida, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'services_12_days',
      name: 'Serviços extras - 12 dias antes',
      trigger_anchor: 'checkin',
      offset_days: -12,
      send_time: '09:00',
      filial_scope: 'all',
      subject: 'Últimos dias para adicionar serviços à sua estadia na {{cabana}}',
      body: <<~BODY
        Olá, {{hospede}}.

        Estamos nos aproximando do prazo final para adicionar serviços à sua estadia.

        Confira as opções no material do hóspede, que fica na primeira mensagem do grupo de estadia no WhatsApp.

        Código da reserva: {{codigo}}

        Qualquer dúvida, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    },
    {
      trigger_key: 'services_last_day',
      name: 'Último dia de serviços',
      trigger_anchor: 'service_deadline',
      offset_days: 0,
      send_time: '09:00',
      filial_scope: 'all',
      subject: 'Último dia para comprar serviços para sua estadia na {{cabana}}',
      body: <<~BODY
        Olá, {{hospede}}.

        Hoje é o último dia para adicionar serviços à sua estadia pelo sistema.

        Depois do prazo, não garantimos a possibilidade de compra de serviços. Não deixe para a última hora e garanta ainda hoje os serviços que deseja incluir na sua experiência.

        Código da reserva: {{codigo}}

        Qualquer dúvida, fale conosco pelo WhatsApp: {{whatsapp}}.

        Atenciosamente,

        Maisa
        Responsável pela curadoria do Villaggio Girotto.
      BODY
    }
  ].freeze

  validates :name, :trigger_key, :trigger_anchor, :filial_scope, :subject, :body, presence: true
  validates :trigger_key, uniqueness: true
  validates :trigger_anchor, inclusion: { in: TRIGGER_ANCHORS.keys }
  validates :filial_scope, inclusion: { in: FILIAL_SCOPES.keys }
  validates :offset_days, numericality: { only_integer: true, greater_than_or_equal_to: -15, less_than_or_equal_to: 15 }

  scope :active, -> { where(active: true) }

  def self.ensure_defaults!
    DEFAULTS.each do |attributes|
      template = find_or_initialize_by(trigger_key: attributes.fetch(:trigger_key))
      next if template.persisted?

      template.assign_attributes(attributes.merge(active: true, system_template: true))
      template.save!
    end
  end

  def removable?
    !system_template?
  end

  def matches_reserva?(reserva)
    return false unless active?
    return true if filial_scope == 'all'

    filial_key(reserva.cabana&.filial) == filial_scope
  end

  def scheduled_at_for(reserva)
    date = anchor_date_for(reserva)
    return if date.blank?

    time = send_time || Time.zone.parse('09:00')
    Time.zone.local(date.year, date.month, date.day, time.hour, time.min)
  end

  def render_subject(reserva)
    interpolate(subject, reserva)
  end

  def render_body(reserva)
    interpolate(body, reserva)
  end

  private

  def anchor_date_for(reserva)
    base_date = case trigger_anchor
                when 'reservation_confirmed'
                  Date.current
                when 'checkin'
                  reserva.start_date
                when 'checkout'
                  reserva.end_date
                when 'service_deadline'
                  reserva.service_purchase_block_date
                when 'first_night'
                  reserva.start_date&.next_day
                end
    base_date&.+(offset_days)
  end

  def interpolate(text, reserva)
    tokens = {
      'codigo' => reserva.id.to_s,
      'hospede' => reserva.guest_name.presence || reserva.user&.name.to_s,
      'cabana' => reserva.cabana&.name.to_s,
      'filial' => reserva.cabana&.filial&.name.to_s,
      'entrada' => reserva.start_date&.strftime('%d/%m/%Y').to_s,
      'saida' => reserva.end_date&.strftime('%d/%m/%Y').to_s,
      'material_url' => public_material_url,
      'maps_url' => reserva.cabana&.filial&.address.to_s.presence || 'Consulte o material do hóspede',
      'whatsapp' => whatsapp_number_for(reserva.cabana&.filial)
    }

    tokens.reduce(text.to_s) do |memo, (key, value)|
      memo.gsub("{{#{key}}}", value.to_s)
    end
  end

  def public_material_url
    host = ENV['PAYMENT_PUBLIC_HOST'].presence ||
           ENV['APP_HOST'].presence ||
           ENV['RENDER_EXTERNAL_HOSTNAME'].presence ||
           'villaggio-stock.onrender.com'
    "https://#{host.sub(%r{\Ahttps?://}, '')}/termos-hospedagem"
  end

  def whatsapp_number_for(filial)
    suffix = filial_key(filial) == 'brauna' ? 'BRAUNA' : 'SERRA'
    ENV["PUBLIC_BOOKING_WHATSAPP_#{suffix}"].presence || ENV['PUBLIC_BOOKING_WHATSAPP_DEFAULT'].to_s
  end

  def filial_key(filial)
    normalized_name = I18n.transliterate(filial&.name.to_s).downcase
    return 'brauna' if normalized_name.include?('brauna')

    'serra'
  end

  def assign_custom_trigger_key
    return if trigger_key.present?

    self.trigger_key = "custom_#{SecureRandom.urlsafe_base64(8)}"
  end

  def cancel_pending_deliveries
    reservation_email_deliveries.pending.update_all(
      status: 'canceled',
      error_message: 'Modelo de e-mail excluído',
      updated_at: Time.current
    )
  end
end
