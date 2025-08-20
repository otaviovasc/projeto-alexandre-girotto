class Admin::CabanasController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin
  before_action :set_cabana, only: [:edit, :update, :destroy, :show, :price_rules_and_holidays, :edit_import_links, :update_import_links]

  def index
    @cabanas = Cabana.all
  end

  def new
    @cabana = Cabana.new
  end

  def create
    @cabana = Cabana.new(cabana_params)

    if @cabana.save
      @cabana.images.attach(params[:cabana][:images]) if params[:cabana][:images].present?
      redirect_to admin_cabanas_path, notice: 'Cabana criada com sucesso.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @cabana.update(cabana_params.except(:images))
      # Verifica se há novas imagens para adicionar
      if params[:cabana][:images].present?
        images = Array(params[:cabana][:images]) # Garante que é um array

        images.each do |image|
          # Verifica se o arquivo é válido antes de anexar
          if image.respond_to?(:original_filename) && !@cabana.images.map(&:filename).include?(image.original_filename)
            @cabana.images.attach(image)
          end
        end
      end

      redirect_to edit_admin_cabana_path(@cabana), notice: 'Cabana atualizada com sucesso.'
    else
      flash.now[:alert] = 'Erro ao atualizar a cabana. Verifique os campos e tente novamente.'
      render :edit
    end
  end

  def edit_import_links
    @import_links = @cabana.import_links.present? ? JSON.parse(@cabana.import_links) : {}
  end

  def update_import_links
    @cabana = Cabana.find(params[:id])
    links = params[:import_links]&.to_unsafe_h&.compact_blank || {}
    @cabana.import_links = links.to_json
    
    if @cabana.save
      redirect_to admin_cabanas_path, notice: "Links atualizados com sucesso!"
    else
      render :edit_import_links
    end
  end
  
  def destroy
    @cabana.destroy
    redirect_to admin_cabanas_path, notice: 'Cabana deletada.'
  end

  def price_rules_and_holidays
    @price_rule = PriceRule.new
    @holidays = Holiday.all
    @holiday = Holiday.new
    @promotion = @cabana.promotions.new
  end

  def remove_image
    @cabana = Cabana.find(params[:id])
    image = @cabana.images.find_by(id: params[:image_id])

    if image
      image.purge_later
      redirect_to edit_admin_cabana_path(@cabana), notice: 'Imagem removida com sucesso.'
    else
      redirect_to edit_admin_cabana_path(@cabana), alert: 'Imagem não encontrada.'
    end
  end

  private

  def set_cabana
    @cabana = Cabana.find(params[:id])
  end

  def cabana_params
    params.require(:cabana).permit(:name, :price, :link_guia, :color, :filial_id, images: [])
  end

  def authorize_admin
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.admin?
  end
end
