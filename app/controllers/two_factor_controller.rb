class TwoFactorController < ApplicationController
  before_action :authenticate_user!

  def send_otp
    current_user.generate_otp!
    # For Emails
    UserMailer.with(user: current_user).send_otp.deliver_later

    # For SMS (optional)
    if current_user.phone_number.present?
      begin
        SmsSender.send_otp(current_user.phone_number, current_user.otp_code)
      rescue StandardError => e
        Rails.logger.warn("Failed to send SMS OTP: #{e.message}")
      end
    end

    redirect_to verify_otp_path, notice: 'OTP sent.'
  end

  def verify; end

  def check
    if current_user.otp_valid?(params[:otp_code])
      session[:two_factor_authenticated] = true
      current_user.clear_otp!
      redirect_to root_path, notice: 'OTP verified.'
    else
      flash.now[:alert] = 'Invalid or expired OTP.'
      render :verify
    end
  end
end
