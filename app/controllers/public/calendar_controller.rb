# app/controllers/public/calendar_controller.rb
module Public
  class CalendarController < ApplicationController
    skip_before_action :authenticate_user! # Se usa Devise ou auth

    def export
      cabana = Cabana.find(params[:id])
      reservas = cabana.reservas.where(payment_status: 'paid') 

      calendar = Icalendar::Calendar.new
      calendar.prodid = "-//Meu Sistema de Reservas//iCal Export//PT-BR"
      calendar.version = '2.0'

      reservas.each do |reserva|
        event = Icalendar::Event.new
        event.dtstart = Icalendar::Values::Date.new(reserva.start_date)
        event.dtend   = Icalendar::Values::Date.new(reserva.end_date + 1) # +1 para não exibir dia final como disponível
        event.summary = "Reserva - #{reserva.user&.name || 'Sem nome'}"
        event.description = "Reserva importada do sistema"
        event.uid = "reserva-#{reserva.id}@meusistema.com"
        calendar.add_event(event)
      end

      calendar.publish

      respond_to do |format|
        format.ics do
          headers['Content-Type'] = 'text/calendar'
          render plain: calendar.to_ical
        end
      end
    end
  end
end
