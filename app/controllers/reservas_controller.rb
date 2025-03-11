require 'httparty'
require 'base64'

class ReservasController < ApplicationController
  layout "clientside"
  before_action :check_reservations_on_new, only: [:new]
  before_action :set_reserva, only: [:show, :pay]
  skip_before_action :verify_authenticity_token, only: [:payment_webhook]
  skip_before_action :authenticate_user!, only: [:new, :unavailable_dates, :calculate_price, :create]

  def index
    @reservas = current_user.reservas.order(:start_date)
    @reservas.each do |reserva|
      if reserva.expired? && (reserva.waiting_payment? || reserva.pending?)
        reserva.update_column(:payment_status, 'canceled')
      end
    end
  end

  def show
    @reserva_services = @reserva.reserva_services.includes(:service)
    @reserva_items = @reserva.reserva_items.includes(:item)
    if @reserva.expired? && (@reserva.waiting_payment? || @reserva.pending?)
      @reserva.update_column(:payment_status, 'canceled')
      flash[:alert] = "O prazo para pagamento expirou. Sua reserva foi cancelada."
      redirect_to reserva_path(@reserva)
    end
  end

  def new
    @cabana = Cabana.find(params[:cabana_id] || session[:cabana_id])
    reserva_data = session[:reserva_params] || {}

    @reserva = @cabana.reservas.new(reserva_data)
    @breakfast_service = Service.find_by(name: 'Café da Manhã')
    @infos_da_cabana = InfoDaCabana.where(cabana_id: @cabana.id)
  end

  def create
    # Se o usuário não estiver logado, salva os parâmetros na sessão e redireciona para login
    unless user_signed_in?
      session[:reserva_params] = reserva_params.to_h
      session[:cabana_id]     = params[:cabana_id]
      redirect_to new_user_session_path, alert: "Por favor, faça login para continuar com a reserva."
      return
    end

    # Se o usuário estiver logado, cria a reserva normalmente
    @cabana  = Cabana.find(params[:cabana_id])
    @reserva = @cabana.reservas.new(reserva_params)
    @reserva.user = current_user

    if @reserva.save
      if params[:reserva][:include_breakfast] == "1"
        service = Service.find_by(name: 'Café da Manhã')
        ReservaService.create(
          reserva: @reserva,
          service: service,
          quantity: params[:reserva][:breakfast_quantity].to_i
        )
      end

      @reserva.calculate_total_price!
      @reserva.update_columns(
        payment_expires_at: 10.minutes.from_now
      )
      UserMailer.reserva_created(current_user, @reserva).deliver_now
      redirect_to reserva_path(@reserva), notice: 'Reserva criada com sucesso.'
    else
      redirect_to new_cabana_reserva_path(@cabana), alert: "ERRO: #{@reserva.errors.full_messages.join("\n")}"
    end
  end

  # Essa ação é chamada após o login (quando os dados da reserva foram armazenados na sessão)
  def auto_create
    unless session[:reserva_params].present? && session[:cabana_id].present?
      redirect_to root_path, alert: "Dados da reserva não encontrados." and return
    end

    cabana = Cabana.find(session.delete(:cabana_id))
    reserva_data = session.delete(:reserva_params)

    # Removendo os campos extras que não fazem parte do modelo (mas são usados para lógica)
    include_breakfast = reserva_data.delete("include_breakfast")
    breakfast_quantity = reserva_data.delete("breakfast_quantity")

    @reserva = cabana.reservas.new(reserva_data)
    @reserva.user = current_user

    if @reserva.save
      if include_breakfast.to_s == "1"
        service = Service.find_by(name: 'Café da Manhã')
        ReservaService.create(
          reserva: @reserva,
          service: service,
          quantity: breakfast_quantity.to_i
        )
      end
      @reserva.calculate_total_price!
      @reserva.update_columns(
        payment_expires_at: 10.minutes.from_now
      )

      redirect_to reserva_path(@reserva), notice: "Reserva criada com sucesso após o login."
    else
      redirect_to new_cabana_reserva_path(cabana), alert: "Erro ao criar reserva: #{@reserva.errors.full_messages.join(', ')}"
    end
  end

  def pay
    # Check if payment_link already exists
    if @reserva.payment_link_url.present?
      redirect_to @reserva.payment_link_url, allow_other_host: true
      return
    end

    api_key = @reserva.cabana.filial.pagarme_api_key
    base64_credentials = Base64.strict_encode64("#{api_key}:password")

    success_url = reserva_url(@reserva)  # URL to redirect after successful payment
    failure_url = reserva_url(@reserva)  # You can customize this if needed for failed payments

    amount_in_cents = (@reserva.total_price * 100).to_i

    response = HTTParty.post(
      'https://api.pagar.me/core/v5/paymentlinks', # https://sdx-api.pagar.me/core/v5/paymentlinks
      headers: {
        'Authorization' => "Basic #{base64_credentials}",
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
      },
      body: {
        is_building: false,
        type: 'order',
        name: "Reserva #{@reserva.id}",
        payment_settings: {
          credit_card_settings: {
            installments_setup: {
              interest_type: 'simple',
              interest_rate: 0,
              max_installments: 1,
              amount: amount_in_cents,
            },
            operation_type: 'auth_and_capture'
          },
          pix_settings: {
            expires_in: 600  # PIX expires in 1 hour
          },
          accepted_payment_methods: [
            'credit_card',
            'pix'
          ]
        },
        cart_settings: {
          items: [
            {
              id: @reserva.id.to_s,
              name: "Reserva de #{@reserva.cabana.name}",
              amount: amount_in_cents,
              unit_price: amount_in_cents,
              default_quantity: 1,
            }
          ]
        },
        max_paid_sessions: 1,
        success_url: success_url,  # Redirect back to this URL on success
        failure_url: failure_url,
      }.to_json
    )

    # Add this to log the full response for debugging
    puts "Response PayReserva Body: #{response}"
    puts "Response PayReserva Code: #{response.code}"

    Rails.logger.info "PagarMe Response: #{response.body}"

    if response.code == 201
      UserMailer.reserva_created(current_user, @reserva).deliver_now
      payment_link = JSON.parse(response.body)

      if payment_link['url'].present?
        @reserva.update_column(:payment_link_id, payment_link['id'])
        @reserva.update_column(:payment_link_url, payment_link['url'])
        @reserva.update_column(:payment_status, 'waiting_payment')
        redirect_to payment_link['url'], allow_other_host: true  # Allow external redirect...
      else
        flash[:alert] = "Erro: Link de pagamento não encontrado."
        redirect_to reserva_path(@reserva)
      end
    else
      flash[:alert] = "Erro ao criar o link de pagamento: #{response.parsed_response['errors'] || response.message}"
      redirect_to reserva_path(@reserva)
    end
  rescue => e
    flash[:alert] = "Erro ao criar o link de pagamento: #{e.message}"
    redirect_to reserva_path(@reserva)
  end

  def payment_webhook
    event = JSON.parse(request.body.read)

    # Verify the event came from Pagar.me (you should implement proper verification)
    payment_link_id = event['id']
    @reserva = Reserva.find_by(payment_link_id: payment_link_id)

    if @reserva.nil?
      render json: { error: 'Reserva não encontrada' }, status: :not_found and return
    end

    status = event['status'] || event['current_status']

    case status
    when 'waiting_payment'
      @reserva.update_column(:payment_status, 'waiting_payment')
    when 'paid'
      UserMailer.reserva_paid(current_user, @reserva).deliver_now
      @reserva.update_column(:payment_status, 'paid')
    when 'unpaid', 'refused'
      @reserva.update_column(:payment_status, 'refused')
    when 'canceled'
      @reserva.update_column(:payment_status, 'canceled')
    end

    head :ok
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  def unavailable_dates
    @cabana = Cabana.find(params[:cabana_id])

    # Filter reservations to include only those that are active and not expired
    reservas = @cabana.reservas.where(payment_status: ['pending', 'waiting_payment', 'paid'])
                               .where("payment_expires_at IS NULL OR payment_expires_at > ?", Time.current)

    # Map the unavailable dates for each active reservation
    unavailable_dates = reservas.map do |reserva|
      (reserva.start_date...reserva.end_date).to_a
    end.flatten

    render json: unavailable_dates
  end


  def calculate_price
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])
    include_breakfast = params[:include_breakfast] == 'true'
    breakfast_quantity = params[:breakfast_quantity].to_i

    cabana = Cabana.find(params[:cabana_id])
    reserva = Reserva.new(start_date: start_date, end_date: end_date, cabana: cabana)

    total_price = reserva.calculate_total_price! || 0  # Ensure total_price is a number

    if include_breakfast
      breakfast_service = Service.find_by(name: 'Café da Manhã')
      days_stayed = (start_date...end_date).count
      total_price += breakfast_service.price * days_stayed * breakfast_quantity
    end

    render json: { total_price: total_price.to_f }  # Ensure total_price is a float
  end

  private

  def check_reservations_on_new
    @cabana = Cabana.find(params[:cabana_id] || session[:cabana_id])
    @cabana.reservas.each do |reserva|
      if reserva.expired? && (reserva.waiting_payment? || reserva.pending?)
        reserva.update_column(:payment_status, 'canceled')
      end
    end
  end

  def set_reserva
    @reserva = current_user.reservas.find(params[:id])
  end

  def reserva_params
    params.require(:reserva).permit(:start_date, :end_date, :include_breakfast, :breakfast_quantity)
  end
end
