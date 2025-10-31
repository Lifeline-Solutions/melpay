class ApplicationController < ActionController::Base
  include CanCan::ControllerAdditions

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :update_allowed_parameters, if: :devise_controller?
  before_action :require_2fa
  skip_before_action :require_2fa, if: -> { devise_controller? || controller_name == 'two_factor' }
  # before_action :authenticate_user!, except: %i[new create]

  def update_allowed_parameters
    devise_parameter_sanitizer.permit(:sign_up) { |u| u.permit(:first_name, :last_name, :email, :password) }
    devise_parameter_sanitizer.permit(:account_update) { |u| u.permit(:first_name, :last_name, :email, :password, :current_password) }
    devise_parameter_sanitizer.permit(:invite, keys: %i[email role])
  end

  def require_2fa
    return unless user_signed_in? && !session[:two_factor_authenticated]

    # If the user is signed in but not 2FA-authenticated, send them to OTP send/verify flow
    redirect_to send_otp_two_factor_path
  end
end
