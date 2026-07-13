class Admin::ServicePurchasesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin

  def index
    @selected_status = params[:status].presence || 'paid'

    @service_purchases = ReservaService
                         .includes(:service, reserva: [:user, { cabana: :filial }])
                         .where.not(payment_status: nil)

    @service_purchases = @service_purchases.where(payment_status: @selected_status) if @selected_status.present?
    @service_purchases = @service_purchases.where(service_date: params[:start_date]..) if params[:start_date].present?
    @service_purchases = @service_purchases.where(service_date: ..params[:end_date]) if params[:end_date].present?

    if params[:q].present?
      term = "%#{params[:q].strip}%"
      @service_purchases = @service_purchases
                           .joins(:service, reserva: [:user, :cabana])
                           .where(
                             'users.name ILIKE :term OR users.email ILIKE :term OR services.name ILIKE :term OR cabanas.name ILIKE :term',
                             term: term
                           )
    end

    @total_paid = @service_purchases.where(payment_status: 'paid').sum(:total_paid)
    @paid_count = @service_purchases.where(payment_status: 'paid').count
    @waiting_count = @service_purchases.where(payment_status: 'waiting_payment').count
    @refused_count = @service_purchases.where(payment_status: 'refused').count

    @service_purchases = @service_purchases.order(Arel.sql('COALESCE(reserva_services.paid_at, reserva_services.updated_at) DESC'))
  end

  def closing
    @selected_month = parse_month(params[:month]) || Date.current.prev_month
    @report = ServiceClosingReport.new(month: @selected_month)
    @filial_reports = @report.filial_reports
  end

  private

  def parse_month(value)
    return if value.blank?

    Date.strptime(value, '%Y-%m')
  rescue ArgumentError
    nil
  end

  def authorize_admin
    redirect_to root_path, alert: 'Voce nao tem permissao para fazer isso.' unless current_user.admin?
  end
end
