class Admin::RecurringMaintenanceRulesController < ApplicationController
  before_action :authorize_admin
  before_action :set_rule, only: [:edit, :update, :destroy, :toggle]
  before_action :load_cabanas, only: [:new, :create, :edit, :update]

  def index
    @rules = RecurringMaintenanceRule.order(active: :desc, first_due_on: :asc, control_title: :asc, title: :asc)
  end

  def new
    @rule = RecurringMaintenanceRule.new(
      active: true,
      frequency_interval: 1,
      frequency_unit: 'monthly',
      first_due_on: Date.current + 1.day
    )
  end

  def create
    @rule = RecurringMaintenanceRule.new
    assign_rule_attributes(@rule)

    if @rule.save
      sync_operational_rules
      redirect_to admin_recurring_maintenance_rules_path, notice: 'Manutenção recorrente criada.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    assign_rule_attributes(@rule)

    if @rule.save
      sync_operational_rules
      redirect_to admin_recurring_maintenance_rules_path, notice: 'Manutenção recorrente atualizada.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy!
    sync_operational_rules
    redirect_to admin_recurring_maintenance_rules_path, notice: 'Manutenção recorrente excluída.'
  end

  def toggle
    @rule.update!(active: !@rule.active?)
    sync_operational_rules

    status = @rule.active? ? 'ativada' : 'pausada'
    redirect_to admin_recurring_maintenance_rules_path, notice: "Manutenção recorrente #{status}."
  end

  private

  def set_rule
    @rule = RecurringMaintenanceRule.find(params[:id])
  end

  def load_cabanas
    @cabanas = Cabana.joins(:filial).includes(:filial).order('filials.name ASC, cabanas.name ASC')
  end

  def assign_rule_attributes(rule)
    attributes = rule_params.to_h
    cabana_ids = attributes.delete('cabana_ids')
    attributes['all_cabanas'] = ActiveModel::Type::Boolean.new.cast(attributes['all_cabanas'])

    rule.assign_attributes(attributes)
    rule.cabana_ids = cabana_ids
  end

  def rule_params
    params.require(:recurring_maintenance_rule).permit(
      :title,
      :control_title,
      :message_body,
      :recipients_text,
      :frequency_interval,
      :frequency_unit,
      :first_due_on,
      :all_cabanas,
      :active,
      cabana_ids: []
    )
  end

  def sync_operational_rules
    FakeHolmyCleaningSync.run if defined?(FakeHolmyCleaningSync)
    RecurringMaintenanceSync.run if defined?(RecurringMaintenanceSync)
    RecurringMaintenanceWhatsappTaskSync.run(date: Date.current) if defined?(RecurringMaintenanceWhatsappTaskSync)
  rescue => e
    Rails.logger.error "Erro ao sincronizar manutenções recorrentes no ADM: #{e.message}"
  end
end
