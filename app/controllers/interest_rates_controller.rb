class InterestRatesController < ApplicationController
  before_action :set_system_setting
  before_action :set_clients, only: [:edit, :manage]

  def index
    @clients = Client.order(:name)
    @global_rate = @system_setting.global_interest_rate
  end

  def manage
    # This action is used for the management page
  end

  def edit
    render :manage
  end

  def update
    if updating_global_rate?
      update_global_rate
    elsif updating_client_rate?
      update_client_rate
    else
      redirect_to interest_rates_path, alert: "Nothing to update."
    end
  end

  # Handle global rate updates
  def update_global
    if @system_setting.update(system_setting_params)
      redirect_to interest_rates_path, notice: "Global interest rate updated."
    else
      flash.now[:alert] = "Failed to update global interest rate."
      @clients = Client.order(:name)
      render :manage
    end
  end

  # Handle custom client rate updates
  def update_custom
    if params[:client].present? && params[:client][:id].present?
      client = Client.find(params[:client][:id])
      if client.update(custom_interest_rate: params[:client][:custom_interest_rate])
        redirect_to interest_rates_path, notice: "Custom interest rate updated for #{client.name}."
      else
        redirect_to manage_interest_rates_path, alert: "Failed to update custom interest rate for #{client.name}."
      end
    else
      redirect_to manage_interest_rates_path, alert: "Please select a client."
    end
  end

  private

  def set_system_setting
    @system_setting = SystemSetting.instance
  end

  def set_clients
    @clients = Client.order(:name)
  end

  def updating_global_rate?
    params[:system_setting].present?
  end

  def updating_client_rate?
    params[:client].present? && params[:client][:id].present?
  end

  def update_global_rate
    if @system_setting.update(system_setting_params)
      redirect_to interest_rates_path, notice: "Global interest rate updated."
    else
      flash.now[:alert] = "Failed to update global interest rate."
      @clients = Client.order(:name)
      render :manage
    end
  end

  def update_client_rate
    client = Client.find(params[:client][:id])
    if client.update(client_params)
      redirect_to interest_rates_path, notice: "Custom interest rate updated for #{client.name}."
    else
      redirect_to interest_rates_path, alert: "Failed to update custom interest rate for #{client.name}."
    end
  end

  def system_setting_params
    params.require(:system_setting).permit(:global_interest_rate)
  end

  def client_params
    params.require(:client).permit(:custom_interest_rate)
  end
end