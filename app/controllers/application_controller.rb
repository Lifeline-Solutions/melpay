class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :update_allowed_parameters, if: :devise_controller?

  def update_allowed_parameters
    devise_parameter_sanitizer.permit(:sign_up) { |u| u.permit(:name, :email, :password) }
    devise_parameter_sanitizer.permit(:account_update) { |u| u.permit(:name, :email, :password, :current_password) }
    devise_parameter_sanitizer.permit(:invite, keys: %i[email role])
  end

  # before_action :require_2fa

  def require_2fa
    return unless user_signed_in? && !session[:two_factor_authenticated]

    redirect_to send_otp_two_factor_path
  end
end
