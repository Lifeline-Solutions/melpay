class ApplicationController < ActionController::Base
  include CanCan::ControllerAdditions

  # Only allow modern browsers
  allow_browser versions: :modern

  # Devise strong parameters
  before_action :update_allowed_parameters, if: :devise_controller?

  # 2FA check (after login)
  before_action :require_2fa, unless: -> { devise_controller? || controller_name == 'two_factor' }

  # PaperTrail - Modified to handle Devise login
  before_action :set_paper_trail_whodunnit

  def update_allowed_parameters
    devise_parameter_sanitizer.permit(:sign_up) { |u| u.permit(:first_name, :last_name, :email, :password) }
    devise_parameter_sanitizer.permit(:account_update) { |u| u.permit(:first_name, :last_name, :email, :password, :current_password) }
    devise_parameter_sanitizer.permit(:invite, keys: %i[email role])
  end

  def require_2fa
    return unless user_signed_in? && !session[:two_factor_authenticated]

    redirect_to send_otp_two_factor_path
  end

  def info_for_paper_trail
    {
      ip: request.remote_ip,
      user_agent: request.user_agent,
      request_id: request.uuid,
      whodunnit_uuid: current_user&.id
    }
  end

  # Override PaperTrail method to handle Devise login scenario
  def set_paper_trail_whodunnit
    # For Devise sessions controller during login, set whodunnit manually after authentication
    if devise_controller? && controller_name == 'sessions' && action_name == 'create'
      # Skip setting whodunnit here - it will be set in SessionsController after user is authenticated
      return
    end

    # For all other cases, we are using the default PaperTrail behavior
    super
  end
end
