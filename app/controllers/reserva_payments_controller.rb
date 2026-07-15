class ReservaPaymentsController < ApplicationController
  layout 'fnrh_portal'

  skip_before_action :authenticate_user!
  before_action :set_reserva_payment

  def show
    @reserva = @reserva_payment.reserva
  end

  def accept_terms
    @reserva = @reserva_payment.reserva

    unless ActiveModel::Type::Boolean.new.cast(params[:terms_accepted])
      flash.now[:alert] = 'Confirme o aceite dos termos para continuar.'
      render :show, status: :unprocessable_entity
      return
    end

    name = params[:terms_acceptance_name].to_s.squish
    if name.split(/\s+/).size < 2
      flash.now[:alert] = 'Informe nome e sobrenome do responsável pela reserva.'
      render :show, status: :unprocessable_entity
      return
    end

    @reserva_payment.update!(
      terms_accepted_at: Time.current,
      terms_acceptance_name: name,
      terms_acceptance_ip: request.remote_ip,
      terms_acceptance_user_agent: request.user_agent
    )

    redirect_to reserva_payment_path(token: @reserva_payment.terms_token), notice: 'Termos aceitos. Você já pode seguir para o pagamento.'
  end

  private

  def set_reserva_payment
    @reserva_payment = ReservaPayment.includes(reserva: [:user, { cabana: :filial }]).find_by!(terms_token: params[:token])
  end
end
