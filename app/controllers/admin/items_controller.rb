class Admin::ItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin_or_manager
  before_action :set_filial
  before_action :set_item, only: [:edit, :update, :destroy, :increment, :decrement]
  before_action :authorize_manager_for_filial

  # GET /filials/:filial_id/items
  def index
    @items = @filial.items.order(:name)
  end

  def critical_stock
    @items = @filial.items.where('quantity <= critical_stock').order(:name)
    render :index
  end

  # GET /filials/:filial_id/items/new
  def new
    @item = @filial.items.build
  end

  # POST /filials/:filial_id/items
  def create
    @item = @filial.items.build(item_params)

    if @item.save
      @item.image.attach(params[:item][:image]) if params[:item][:image].present?
      redirect_to admin_filial_items_path(@filial), notice: "#{@item.name} criado com sucesso."
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
      @item.image.attach(params[:item][:image]) if params[:item][:image].present?
      redirect_to admin_filial_items_path(@filial), notice: "#{@item.name} foi atualizado para #{@item.quantity}"
    else
      render :edit
    end
  end

  # DELETE /filials/:filial_id/items/:id
  def destroy
    name = @item.name
    @item.destroy
    redirect_to admin_filial_items_path(@filial), notice: "#{name} foi deletado com sucesso."
  end

  # PATCH /filials/:filial_id/items/:id/increment
  def increment
    @item.increment!(:quantity)
    redirect_to admin_filial_items_path(@filial), notice: 'Item quantity was successfully increased.'
  end

  # PATCH /filials/:filial_id/items/:id/decrement
  def decrement
    @item.decrement!(:quantity) if @item.quantity > 0
    redirect_to admin_filial_items_path(@filial), notice: 'Item quantity was successfully decreased.'
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
    params.require(:item).permit(:name, :quantity, :category, :critical_stock)
  end

  def authorize_admin_or_manager
    redirect_to root_path, alert: 'Você não tem permissão para fazer isso.' unless current_user.manager? || current_user.admin?
  end

  def authorize_manager_for_filial
    if current_user.manager? && current_user.filial != @filial
      redirect_to root_path, alert: 'Você não tem acesso à essa filial.'
    end
  end
end
