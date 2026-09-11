class PartnershipDiscountCouponsController < ApplicationController
  before_action :ensure_coupon_access!
  before_action :set_coupon, only: [:edit, :update, :destroy]

  def index
    @coupons = PartnershipDiscountCoupon.order(active: :desc, created_at: :desc)
  end

  def new
    @coupon = PartnershipDiscountCoupon.new(active: true)
  end

  def create
    @coupon = PartnershipDiscountCoupon.new(coupon_params)
    @coupon.created_by = current_user

    if @coupon.save
      redirect_to partnership_discount_coupons_path, notice: 'Cupom criado.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @coupon.update(coupon_params)
      redirect_to partnership_discount_coupons_path, notice: 'Cupom atualizado.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @coupon.update!(active: false)
    redirect_to partnership_discount_coupons_path, notice: 'Cupom desativado.'
  end

  private

  def ensure_coupon_access!
    return if current_user&.admin? || current_user&.partnership_agent?

    redirect_to root_path, alert: 'Acesso não autorizado.'
  end

  def set_coupon
    @coupon = PartnershipDiscountCoupon.find(params[:id])
  end

  def coupon_params
    params.require(:partnership_discount_coupon).permit(:code, :discount_percent, :active)
  end
end
