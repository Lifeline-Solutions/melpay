class UserMailer < ApplicationMailer
  default from: 'noreply@malpayments.com'

  def send_otp
    @user = params[:user]
    mail(to: @user.email, subject: 'Your OTP Code')
  end
end
