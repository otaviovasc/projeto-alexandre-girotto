class Admin::PriceRulesController < ApplicationController
  def create
    @cabana = Cabana.find(params[:cabana_id])
    @price_rule = PriceRule.new(price_rule_params)
    @price_rule.cabana_id = @cabana.id
    if @price_rule.save
      flash[:notice] = "Price rule created successfully."
    end
    redirect_to price_rules_and_holidays_admin_cabana_path(@cabana)
  end

  def destroy
    @cabana = Cabana.find(params[:cabana_id])
    @price_rule = PriceRule.find(params[:id])
    @price_rule.destroy
    flash[:notice] = "Price rule deleted successfully."
    redirect_to price_rules_and_holidays_admin_cabana_path(@cabana)
  end

  private

  def price_rule_params
    params.require(:price_rule).permit(:cabana_id, :day_type, :price)
  end
end
