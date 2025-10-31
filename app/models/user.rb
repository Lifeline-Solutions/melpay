class User < ApplicationRecord
  rolify
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :invitable, :database_authenticatable, :registerable, :recoverable, :rememberable,
         :validatable, :confirmable, :lockable, :timeoutable, :trackable, :invitable

  has_many :homes, dependent: :destroy
  belongs_to :client
  after_create :default_role

  def default_role
    return if invited_by_id.present?

    add_role(:client) if roles.blank?
  end

  def generate_otp!
    self.otp_code = rand(100_000..999_999).to_s
    self.otp_sent_at = Time.current
    save!
  end

  # OTP is valid for 5 minutes
  def otp_valid?(code)
    otp_code == code && otp_sent_at.present? && otp_sent_at > 5.minutes.ago
  end

  # Clear OTP after successful verification
  def clear_otp!
    update(otp_code: nil, otp_sent_at: nil)
  end
end
