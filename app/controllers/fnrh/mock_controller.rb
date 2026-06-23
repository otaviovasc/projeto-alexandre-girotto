module Fnrh
  class MockController < ApplicationController
    layout 'fnrh_portal'
    skip_before_action :authenticate_user!
    before_action :ensure_mock_mode
    before_action :set_reserva

    def precheckin
    end

    def complete_precheckin
      TransitionService.new(@reserva, source: 'guest').complete_precheckin
      session[:fnrh_portal_reserva_id] = @reserva.id
      redirect_to fnrh_portal_information_path, notice: 'Pré-check-in simulado concluído.'
    rescue => e
      redirect_to fnrh_mock_precheckin_path(@reserva.fnrh_reservation_id), alert: e.message
    end

    private

    def ensure_mock_mode
      head :not_found unless Configuration.mock?
    end

    def set_reserva
      @reserva = Reserva.includes(:user, cabana: :filial).find_by!(fnrh_reservation_id: params[:reservation_id])
    end
  end
end
