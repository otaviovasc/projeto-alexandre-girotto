class Admin::ReservaServicesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin

  def photo_print_pdf
    reserva_service = ReservaService.find(params[:id])

    unless reserva_service.photo_print_pdf.attached?
      redirect_to admin_reserva_path(reserva_service.reserva), alert: 'PDF das fotos não encontrado.' and return
    end

    redirect_to rails_blob_url(reserva_service.photo_print_pdf, disposition: 'attachment'), allow_other_host: true
  end

  private

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
