class Admin::ReservationEmailTemplatesController < ApplicationController
  before_action :require_admin!
  before_action :set_template, only: [:edit, :update, :destroy]

  def index
    ReservationEmailTemplate.ensure_defaults!
    @setting = EmailAutomationSetting.current
    @templates = ReservationEmailTemplate.order(:trigger_anchor, :offset_days, :send_time, :name)
  end

  def edit
  end

  def new
    @template = ReservationEmailTemplate.new(
      active: true,
      trigger_anchor: 'checkin',
      offset_days: -7,
      send_time: '09:00',
      filial_scope: 'all',
      subject: '',
      body: ''
    )
  end

  def create
    @template = ReservationEmailTemplate.new(template_params.merge(system_template: false))

    if @template.save
      redirect_to admin_reservation_email_templates_path, notice: 'Modelo de e-mail criado.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @template.update(template_params)
      redirect_to admin_reservation_email_templates_path, notice: 'Modelo de e-mail atualizado.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @template.system_template?
      redirect_to admin_reservation_email_templates_path, alert: 'Modelos padrão não podem ser excluídos. Pause o modelo se não quiser usá-lo.'
      return
    end

    @template.destroy!
    redirect_to admin_reservation_email_templates_path, notice: 'Modelo de e-mail excluído.'
  end

  def toggle
    setting = EmailAutomationSetting.current

    if setting.enabled?
      setting.pause!(current_user)
      redirect_to admin_reservation_email_templates_path, notice: 'Envio automático de e-mails pausado.'
    else
      setting.resume!
      redirect_to admin_reservation_email_templates_path, notice: 'Envio automático de e-mails retomado.'
    end
  end

  private

  def require_admin!
    redirect_to root_path, alert: 'Acesso restrito.' unless current_user&.admin?
  end

  def set_template
    @template = ReservationEmailTemplate.find(params[:id])
  end

  def template_params
    params.require(:reservation_email_template).permit(
      :name,
      :trigger_anchor,
      :offset_days,
      :send_time,
      :filial_scope,
      :subject,
      :body,
      :active
    )
  end
end
