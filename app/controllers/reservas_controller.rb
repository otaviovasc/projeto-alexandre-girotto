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
    @reserva.user = current_user if user_signed_in?
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
    current_user.sync_filial_from_cabana!(@cabana)
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

      @reserva.update_columns(
        total_price: @reserva.calculate_total_price!,
        payment_expires_at: 10.minutes.from_now
      )
      UserMailer.reserva_created(current_user, @reserva).deliver_now
      UserMailer.notify_adm(current_user, @reserva).deliver_now
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
    current_user.sync_filial_from_cabana!(cabana)

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
      @reserva.update_columns(
        total_price: @reserva.calculate_total_price!,
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

    expires_in = 10
    payment_link = PagarmePaymentLinkService.new(
      api_key: @reserva.cabana.filial.pagarme_api_key_for_payments,
      name: "Reserva #{@reserva.id}",
      order_code: "reserva-#{@reserva.id}",
      items: [{
        id: @reserva.id,
        name: "Reserva de #{@reserva.cabana.name}",
        unit_price: @reserva.total_price,
        quantity: 1
      }],
      success_url: reserva_url(@reserva),
      failure_url: reserva_url(@reserva),
      expires_in: expires_in
    ).call

    UserMailer.reserva_created(current_user, @reserva).deliver_now
    UserMailer.notify_adm(current_user, @reserva).deliver_now

    @reserva.update_columns(
      payment_link_id: payment_link['id'],
      payment_link_url: payment_link['url'],
      payment_status: 'waiting_payment',
      payment_expires_at: expires_in.minutes.from_now
    )

    redirect_to payment_link['url'], allow_other_host: true
  rescue PagarmePaymentLinkService::Error => e
    Rails.logger.error("Pagar.me reserva payment error: #{e.message}")
    flash[:alert] = e.message
    redirect_to reserva_path(@reserva)
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
      UserMailer.notify_adm(current_user, @reserva).deliver_now
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
                               .where(blocks_availability: true)
                               .where("payment_expires_at IS NULL OR payment_expires_at > ?", Time.current)
    
    # Exclui a reserva atual ao editar (para permitir selecionar as próprias datas)
    if params[:exclude_reserva_id].present?
      reservas = reservas.where.not(id: params[:exclude_reserva_id])
    end

    # Collection of dates that are the middle of a stay (completely unavailable)
    fully_unavailable_dates = []
    # Collection of dates that are already a start date for some reservation
    start_dates = []
    # Collection of dates that are already an end date for some reservation
    end_dates = []
    operational_blocks = []

    # Categorize dates
    reservas.each do |reserva|
      availability_start = reserva.availability_start_date
      availability_end = reserva.availability_end_date

      if reserva.early_checkin?
        operational_blocks << {
          date: reserva.early_checkin_block_date,
          type: 'early_checkin',
          color: reserva.cabana.color
        }
      end
      if reserva.late_checkout?
        operational_blocks << {
          date: reserva.late_checkout_block_date,
          type: 'late_checkout',
          color: reserva.cabana.color
        }
      end

      if availability_start == availability_end
        # Single day reservation - fully unavailable
        fully_unavailable_dates << availability_start
      else
        # Multi-day reservation
        start_dates << availability_start
        end_dates << availability_end
        # Middle days are completely unavailable
        ((availability_start + 1)...availability_end).each do |date|
          fully_unavailable_dates << date
        end
      end
    end

    disabled_dates = (fully_unavailable_dates + start_dates).compact.uniq

    if ActiveModel::Type::Boolean.new.cast(params[:details])
      render json: {
        disabled_dates: disabled_dates,
        operational_blocks: operational_blocks
      }
    else
      render json: disabled_dates
    end
  end


  def calculate_price
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])
    include_breakfast = params[:include_breakfast] == 'true'
    breakfast_quantity = params[:breakfast_quantity].to_i

    cabana = Cabana.find(params[:cabana_id])
    reserva = Reserva.new(start_date: start_date, end_date: end_date, cabana: cabana)
    reserva.user = current_user if user_signed_in?

    total_price = reserva.calculate_total_price! || 0  # Ensure total_price is a number

    if include_breakfast
      breakfast_service = Service.find_by(name: 'Café da Manhã')
      days_stayed = (start_date...end_date).count
      total_price += breakfast_service.price_for(reserva) * days_stayed * breakfast_quantity
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
