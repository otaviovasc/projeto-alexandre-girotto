class ItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin_or_manager
  before_action :set_filial
  before_action :set_item, only: [:edit, :update, :destroy, :increment, :decrement]
  before_action :authorize_manager_or_admin_for_filial

  # GET /filials/:filial_id/items
  def index
    @items = @filial.items
  end

  # GET /filials/:filial_id/items/new
  def new
    @item = @filial.items.build
  end

  # POST /filials/:filial_id/items
  def create
    @item = @filial.items.build(item_params)
    if @item.save
      redirect_to filial_items_path(@filial), notice: 'Item was successfully created.'
    else
      render :new
    end
  end

  # GET /filials/:filial_id/items/:id/edit
  def edit
  end

  # PATCH/PUT /filials/:filial_id/items/:id
  def update
    if @item.update(item_params)
      redirect_to filial_items_path(@filial), notice: 'Item was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /filials/:filial_id/items/:id
  def destroy
    @item.destroy
    redirect_to filial_items_path(@filial), notice: 'Item was successfully deleted.'
  end

  # PATCH /filials/:filial_id/items/:id/increment
  def increment
    @item.increment!(:quantity)
    redirect_to filial_items_path(@filial), notice: 'Item quantity was successfully increased.'
  end

  # PATCH /filials/:filial_id/items/:id/decrement
  def decrement
    @item.decrement!(:quantity) if @item.quantity > 0
    redirect_to filial_items_path(@filial), notice: 'Item quantity was successfully decreased.'
  end

  private

  def set_filial
    if params[:filial_id]
      @filial = Filial.find(params[:filial_id])
    else
      @filial = current_user.filial
    end
  end

  def set_item
    @item = @filial.items.find(params[:id])
  end

  def item_params
    params.require(:item).permit(:name, :quantity, :category)
  end

  def authorize_admin_or_manager
    redirect_to root_path, alert: 'You are not authorized to perform this action.' unless current_user.manager? || current_user.admin?
  end

  def authorize_manager_or_admin_for_filial
    if current_user.manager? && current_user.filial != @filial
      redirect_to root_path, alert: 'You are not authorized to access this filial.'
    end
  end
end
