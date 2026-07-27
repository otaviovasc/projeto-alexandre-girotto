class Admin::ReservationWhatsappTasksController < ApplicationController
  before_action :authorize_admin_or_operations_viewer
  before_action :set_no_cache_headers
  before_action :set_task, only: [:update]

  def index
    ReservationWhatsappTaskMaterializer.run(date: Date.current)

    @tasks = visible_tasks
    @pending_tasks = @tasks.reject(&:completed?)
    @pending_by_template = @pending_tasks.group_by(&:template_name)
  end

  def update
    if params[:sent] == '1'
      @task.update!(completed_at: Time.current)
    else
      @task.update!(completed_at: nil)
    end

    redirect_to admin_reservation_whatsapp_tasks_path, notice: 'Mensagem atualizada.'
  end

  private

  def visible_tasks
    ReservationWhatsappTask
      .visible_on(Date.current)
      .includes(:reservation_email_template, reserva: [:user, { cabana: :filial }])
      .to_a
      .select { |task| task.reservation_email_template&.active? }
      .sort_by do |task|
        priority =
          if task.overdue?
            0
          elsif task.completed?
            2
          else
            1
          end

        [priority, task.scheduled_at, task.id]
      end
  end

  def set_task
    @task = ReservationWhatsappTask.find(params[:id])
  end

  def set_no_cache_headers
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  end
end
