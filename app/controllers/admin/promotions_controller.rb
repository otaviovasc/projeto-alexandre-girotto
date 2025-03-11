class Admin::PromotionsController < ApplicationController
  before_action :set_cabana

  def create
    @promotion = @cabana.promotions.build(promotion_params)
    if @promotion.save
      flash[:notice] = "Promoção criada com sucesso."
    else
      flash[:alert] = @promotion.errors.full_messages.join(", ")
    end
    redirect_to price_rules_and_holidays_admin_cabana_path(@cabana)
  end

  def destroy
    @promotion = @cabana.promotions.find(params[:id])
    @promotion.destroy
    flash[:notice] = "Promoção removida com sucesso."
    redirect_to price_rules_and_holidays_admin_cabana_path(@cabana)
  end

  private

  def set_cabana
    @cabana = Cabana.find(params[:cabana_id])
  end

  def promotion_params
    params.require(:promotion).permit(:date, :start_date, :end_date, :price, :is_interval)
  end
end
