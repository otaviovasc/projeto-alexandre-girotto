module ReservasHelper
  def status_translate(status)
    {
      'pending' => 'Pendente',
      'waiting_payment' => 'Aguardando Pagamento',
      'paid' => 'Pago',
      'late_paid' => 'Pago após vencimento',
      'refused' => 'Recusado',
      'canceled' => 'Cancelado'
    }[status] || status
  end

  def badge_class(status)
    case status
    when 'pending' then 'bg-warning'         # Amarelo para pendente
    when 'waiting_payment' then 'bg-secondary' # Cinza para aguardando pagamento
    when 'paid' then 'bg-success'           # Verde para pago
    when 'late_paid' then 'bg-warning text-dark'
    when 'refused' then 'bg-danger'         # Vermelho para recusado
    when 'canceled' then 'bg-dark'          # Preto para cancelado
    else 'bg-light text-dark'               # Branco padrão
    end
  end

  def calendar_reservation_segments(reserva, date)
    segments = []

    if date.between?(reserva.start_date, reserva.end_date)
      css_class = if reserva.start_date == reserva.end_date
                    'start-end'
                  elsif date == reserva.start_date
                    'start'
                  elsif date == reserva.end_date
                    'end'
                  else
                    'middle'
                  end
      joins_operational = (date == reserva.start_date && reserva.early_checkin?) ||
                          (date == reserva.end_date && reserva.late_checkout?)
      segments << { css_class: css_class, operational: false, joins_operational: joins_operational }
    end

    if reserva.early_checkin?
      segments << { css_class: 'start', operational: true, operational_type: 'early-checkin' } if date == reserva.start_date - 1.day
      segments << { css_class: 'end', operational: true, operational_type: 'early-checkin' } if date == reserva.start_date
    end

    if reserva.late_checkout?
      segments << { css_class: 'start', operational: true, operational_type: 'late-checkout' } if date == reserva.end_date
      segments << { css_class: 'end', operational: true, operational_type: 'late-checkout' } if date == reserva.end_date + 1.day
    end

    segments
  end

  def calendar_reservation_code_date?(reserva, date)
    return false if reserva.start_date.blank? || reserva.end_date.blank?

    date == reserva.start_date
  end
end
