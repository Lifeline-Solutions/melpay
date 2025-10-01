class InterestRatesController < ApplicationController
  before_action :set_system_setting

  def edit
    @clients = Client.all
  end

  def update
    if params[:system_setting].present?
      # Update global interest rate
      if @system_setting.update(system_setting_params)
        flash[:notice] = "Global interest rate updated."
      else
        flash[:alert] = "Failed to update global interest rate."
      end
    elsif params[:client].present?
      # Update custom interest rate for a client
      client = Client.find(params[:client][:id])
      if client.update(client_params)
        flash[:notice] = "Custom interest rate updated for #{client.name}."
      else
        flash[:alert] = "Failed to update custom interest rate."
      end
    end

    redirect_to edit_interest_rates_path
  end

  private

  def set_system_setting
    @system_setting = SystemSetting.instance
  end

  def system_setting_params
    params.require(:system_setting).permit(:global_interest_rate)
  end

  def client_params
    params.require(:client).permit(:custom_interest_rate)
  end
end