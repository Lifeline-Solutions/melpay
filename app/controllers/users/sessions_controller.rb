class Users::SessionsController < Devise::SessionsController
  # POST /resource/sign_in
  def create
    self.resource = warden.authenticate!(auth_options)

    # Manually set PaperTrail whodunnit for this specific action
    PaperTrail.request.whodunnit = resource.id.to_s

    # Sign in but require 2FA before granting full access
    sign_in(resource_name, resource)

    # Create login event tracked by PaperTrail
    LoginEvent.create!(
      user: resource,
      ip: request.remote_ip,
      user_agent: request.user_agent,
      session_id: session.id.to_s
    )

    # mark 2FA as not completed
    session[:two_factor_authenticated] = false

    # generate and send OTP
    resource.generate_otp!
    UserMailer.with(user: resource).send_otp.deliver_later

    # Optionally send SMS if phone present (non-blocking)
    if resource.phone_number.present?
      begin
        SmsSender.send_otp(resource.phone_number, resource.otp_code)
      rescue StandardError => e
        Rails.logger.warn("Failed to send SMS OTP: #{e.message}")
      end
    end

    redirect_to verify_otp_path, notice: 'A verification code has been sent to your email.'
  end

  # DELETE /resource/sign_out
  def destroy
    # Manually set PaperTrail whodunnit for logout
    PaperTrail.request.whodunnit = current_user.id.to_s if current_user

    # Create logout event tracked by PaperTrail
    if current_user
      LogoutEvent.create!(
        user: current_user,
        ip: request.remote_ip,
        user_agent: request.user_agent,
        session_id: session.id.to_s
      )
    end

    # clear 2FA session flag
    session.delete(:two_factor_authenticated)
    super
  end

  # Keep other Devise behavior
end
