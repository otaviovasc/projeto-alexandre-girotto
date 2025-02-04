module ReservasHelper
  def status_translate(status)
    {
      'pending' => 'Pendente',
      'waiting_payment' => 'Aguardando Pagamento',
      'paid' => 'Pago',
      'refused' => 'Recusado',
      'canceled' => 'Cancelado'
    }[status] || status
  end

  def badge_class(status)
    case status
    when 'pending' then 'bg-warning'         # Amarelo para pendente
    when 'waiting_payment' then 'bg-secondary' # Cinza para aguardando pagamento
    when 'paid' then 'bg-success'           # Verde para pago
    when 'refused' then 'bg-danger'         # Vermelho para recusado
    when 'canceled' then 'bg-dark'          # Preto para cancelado
    else 'bg-light text-dark'               # Branco padrão
    end
  end
end
