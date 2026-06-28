# app/controllers/services_controller.rb
class ServicesController < ApplicationController
  layout "clientside"
  def show
    @service = Service.find(params[:id])
    @reserva = current_user.reservas
                           .where(payment_status: 'paid')
                           .where('end_date >= ?', Date.current)
                           .order(start_date: :asc, created_at: :desc)
                           .first
    @reserva ||= current_user.reservas.where(payment_status: 'paid').order(created_at: :desc).first
  end
end
