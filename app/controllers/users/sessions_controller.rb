class Users::SessionsController < Devise::SessionsController
  # POST /resource/sign_in
  def create
    self.resource = warden.authenticate!(auth_options)
    # Sign in but require 2FA before granting full access
    sign_in(resource_name, resource)

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
    # clear 2FA session flag
    session.delete(:two_factor_authenticated)
    super
  end

  # Keep other Devise behavior
end
