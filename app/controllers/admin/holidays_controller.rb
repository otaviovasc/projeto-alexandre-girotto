class Admin::HolidaysController < ApplicationController
  def create
    @holiday = Holiday.new(holiday_params)
    if @holiday.save
      flash[:notice] = "Holiday created successfully."
    end
    redirect_back(fallback_location: root_path)
  end

  def destroy
    @holiday = Holiday.find(params[:id])
    @holiday.destroy
    flash[:notice] = "Holiday deleted successfully."
    redirect_back(fallback_location: root_path)
  end

  private

  def holiday_params
    params.require(:holiday).permit(:name, :date)
  end
end
