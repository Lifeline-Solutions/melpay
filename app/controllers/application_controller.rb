class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :update_allowed_parameters, if: :devise_controller?
  before_action :authenticate_user!, except: %i[new create]
  set_current_tenant_through_filter
  before_action :set_tenant

  def update_allowed_parameters
    devise_parameter_sanitizer.permit(:sign_up) { |u| u.permit(:first_name, :last_name, :email, :password) }
    devise_parameter_sanitizer.permit(:account_update) { |u| u.permit(:first_name, :last_name, :email, :password, :current_password) }
    devise_parameter_sanitizer.permit(:invite, keys: %i[email role])
  end

  # before_action :require_2fa

  def require_2fa
    return unless user_signed_in? && !session[:two_factor_authenticated]

    redirect_to send_otp_two_factor_path
  end

  private

  # ruby
  def set_tenant
    subdomain = request.subdomains.first
    if subdomain.present?
      client = Client.find_by(name: subdomain)
      if client
        ActsAsTenant.current_tenant = client
      else
        fallback_client = Client.find_by(name: 'localhost') || Client.first
        if fallback_client
          ActsAsTenant.current_tenant = fallback_client
          Rails.logger.warn "Tenant not found for subdomain '#{subdomain}', using fallback client '#{fallback_client.name}'."
        else
          Rails.logger.error "No suitable tenant found for subdomain '#{subdomain}' or fallback."
          redirect_to root_path, alert: "Tenant not found for subdomain '#{subdomain}'." and return
        end
      end
    else
      # No subdomain, fallback to default client
      fallback_client = Client.find_by(name: 'localhost') || Client.first
      if fallback_client
        ActsAsTenant.current_tenant = fallback_client
        Rails.logger.warn "No subdomain present, using fallback client '#{fallback_client.name}'."
      else
        Rails.logger.error 'No suitable tenant found for request with no subdomain.'
        redirect_to root_path, alert: 'Tenant not found for request with no subdomain.' and return
      end
    end
  end
end
