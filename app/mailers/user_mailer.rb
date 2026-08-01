class UserMailer < ApplicationMailer
  default from: 'Villaggio Girotto <contato@villaggiogirotto.com.br>'

  def welcome_email(user = nil, generated_password = nil)
    @user = user || params[:user]
    @password = generated_password || params[:generated_password]
    @url  = 'https://www.villaggiogirotto.com.br/users/sign_in'
    mail(to: @user.email, subject: 'Sua hospedagem - Villaggio')
  end

  def reserva_created(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/reservas/#{reserva.id}"
    @services = reserva.services.includes(:reserva_services)
    mail(to: @user.email, subject: 'Aguardando Pagamento - Villaggio')
  end

  def reserva_paid(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/reservas/#{reserva.id}"
    @services = reserva.services.includes(:reserva_services)
    mail(to: @user.email, subject: 'Pagamento Confirmado - Villaggio')
  end

  def notify_adm(user, reserva)
    @user = user
    @reserva = reserva
    @url  = "https://www.villaggiogirotto.com.br/admin/reservas_summary"
    mail(to: 'contato@villaggiogirotto.com.br', subject: "Reserva: #{reserva.payment_status} - Villaggio")
  end

  def public_booking_confirmed(user, reserva)
    return if EmailAutomationSetting.enabled?

    @user = user
    @reserva = reserva
    @reserva_payment = reserva.reserva_payments.to_a.find(&:public_booking?) ||
                       reserva.reserva_payments.order(paid_at: :desc).first
    @services = reserva.reserva_services
                       .includes(:service)
                       .where(payment_order_code: @reserva_payment&.payment_order_code)
                       .order(:service_date, :id)
    @service_email_items = public_booking_service_email_items
    @daily_total = public_booking_daily_total
    @services_total = @service_email_items.sum { |item| item[:total] }
    @total_paid = @reserva_payment&.amount || (@daily_total + @services_total)
    host = ENV['APP_HOST'].presence || ENV['RENDER_EXTERNAL_HOSTNAME'].presence || 'villaggio-stock.onrender.com'
    @url = "https://#{host.sub(%r{\Ahttps?://}, '')}/reserva-online-teste/confirmacao/#{@reserva_payment&.terms_token}"

    mail(to: @user.email, subject: "Reserva confirmada ##{@reserva.id} - Villaggio Girotto")
  end

  def reservation_automation(delivery)
    @delivery = delivery
    @reserva = delivery.reserva
    @body = delivery.body

    mail(to: delivery.recipient_email, subject: delivery.subject)
  end

  private

  def public_booking_daily_total
    daily_total = @reserva_payment&.public_booking_daily_total || 0.to_d
    if daily_total.zero? && @service_email_items.blank? && @reserva.total_price.present?
      @reserva.total_price
    else
      daily_total
    end
  end

  def public_booking_service_email_items
    public_booking_services = @reserva_payment&.public_booking_services || []
    visible_reserva_services = @services.reject { |reserva_service| reserva_service.service&.hidden_from_guests? }
    visible_public_booking_services = public_booking_services.reject { |service_payload| Service.hidden_from_guest_name?(service_payload['name']) }

    if visible_reserva_services.any?
      visible_reserva_services.map do |reserva_service|
        quantity = reserva_service.quantity.to_i
        unit_price = reserva_service.unit_price_paid.presence || reserva_service.service.price || 0
        {
          name: reserva_service.service.name,
          service_date: reserva_service.service_date,
          date_pending: false,
          quantity: quantity,
          total: reserva_service.total_paid.presence || (unit_price * quantity)
        }
      end
    elsif visible_public_booking_services.any?
      visible_public_booking_services.filter_map do |service_payload|
        {
          name: service_payload['name'],
          service_date: ActiveModel::Type::Boolean.new.cast(service_payload['date_pending']) ? nil : parse_mailer_date(service_payload['service_date']),
          date_pending: ActiveModel::Type::Boolean.new.cast(service_payload['date_pending']),
          quantity: service_payload['quantity'].to_i,
          total: decimal_value(service_payload['total'])
        }
      end
    else
      []
    end
  end

  def parse_mailer_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def decimal_value(value)
    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    0.to_d
  end
end
