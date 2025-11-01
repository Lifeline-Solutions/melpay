class InterestRatesController < ApplicationController
  before_action :set_system_setting
  before_action :set_clients, only: %i[edit manage]
  before_action :authorize_super_admin!

  def index
    @clients = Client.all.order(:name)
    @nil_interest_rate_count = @clients.where(custom_interest_rate: nil).count
    @custom_count = @clients.where.not(custom_interest_rate: nil).count
    @global_count = @clients.where(custom_interest_rate: nil).count
    @global_rate = @system_setting.global_interest_rate
  end

  def manage
    # This action is used for the management page
  end

  def edit
    render :manage
  end

  def update_global
    if @system_setting.update(system_setting_params)
      redirect_to interest_rates_path, notice: 'Global commission settings updated.'
    else
      flash.now[:alert] = 'Failed to update global commission settings.'
      @clients = Client.order(:name)
      render :manage
    end
  end

  def update_custom
    if params[:client].present? && params[:client][:id].present?
      client = Client.find(params[:client][:id])
      
      # Prepare update attributes
      update_attrs = {}
      
      if params[:client][:commission_type].present?
        update_attrs[:commission_type] = params[:client][:commission_type]
        
        if params[:client][:commission_type] == 'percentage'
          update_attrs[:custom_interest_rate] = params[:client][:custom_interest_rate]
          update_attrs[:fixed_commission_amount] = nil
        elsif params[:client][:commission_type] == 'fixed'
          update_attrs[:fixed_commission_amount] = params[:client][:fixed_commission_amount]
          update_attrs[:custom_interest_rate] = nil
        end
      else
        # Reset to use global settings
        update_attrs[:commission_type] = nil
        update_attrs[:custom_interest_rate] = nil
        update_attrs[:fixed_commission_amount] = nil
      end
      
      if client.update(update_attrs)
        redirect_to interest_rates_path, notice: "Custom commission updated for #{client.name}."
      else
        redirect_to manage_interest_rates_path, alert: "Failed to update custom commission for #{client.name}."
      end
    else
      redirect_to manage_interest_rates_path, alert: 'Please select a client.'
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
      redirect_to interest_rates_path, notice: 'Global interest rate updated.'
    else
      flash.now[:alert] = 'Failed to update global interest rate.'
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

  def authorize_super_admin!
    return if current_user.has_role?(:super_admin)

    redirect_to root_path, alert: 'Access Denied'
  end

  def system_setting_params
    params.require(:system_setting).permit(:global_interest_rate, :commission_type, :fixed_commission_amount)
  end

  def client_params
    params.require(:client).permit(:custom_interest_rate, :commission_type, :fixed_commission_amount)
  end
end
