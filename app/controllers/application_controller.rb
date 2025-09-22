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

  def set_tenant
    # ActsAsTenant.current_tenant = Client.find_by(name: request.domain)
    client = Client.find_by(name: request.domain)
    if client
      ActsAsTenant.current_tenant = client
    else
      # You can customize this behavior as needed (e.g., render 404, redirect, etc.)
      redirect_to root_path, alert: "Tenant not found for domain '#{request.domain}'." and return
    end
  end
end
