class Admin::FunilMailersController < ApplicationController
  def index
    # Inicializa o Ransack com os parâmetros recebidos (se houver)
    @q = FunilMailer.ransack(params[:q])
    # Aplica o filtro, ordena por data de criação e pagina os resultados (10 por página, por exemplo)
    @funil_mailers = @q.result(distinct: true)
                       .order(created_at: :desc)
                       .page(params[:page])
                       .per(10)
  end

end
