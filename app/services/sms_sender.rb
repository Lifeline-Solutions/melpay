class SmsSender
  # Simple wrapper for sending SMS. Replace implementation with real provider (Twilio, Nexmo, etc.).
  def self.send_otp?(phone_number, code)
    Rails.logger.info("Sending OTP #{code} to #{phone_number}")
    # Implement actual provider call here, e.g.
    # client = Twilio::REST::Client.new(ENV['TWILIO_SID'], ENV['TWILIO_TOKEN'])
    # client.messages.create(from: ENV['TWILIO_FROM'], to: phone_number, body: "Your OTP is: #{code}")
    true
  end
end
