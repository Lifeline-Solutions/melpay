class User < ApplicationRecord
  rolify
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :invitable, :database_authenticatable, :registerable, :recoverable, :rememberable,
         :validatable, :confirmable, :lockable, :timeoutable, :trackable

  has_many :homes, dependent: :destroy
  belongs_to :client
  after_create :default_role
  before_create :ensure_user_pass

  # Curated list of common, memorable six-letter English words (lowercase)
  WORDLIST = %w[
    planet orange butter summer credit travel flower silver family garden marble
    pepper castle friend little market monkey guitar kitten rocket canyon valley
    donkey velvet stream anchor island forest coffee harbor walnut sailor candle
    bishop museum domain copper sphere fossil ribbon artist grainy cotton marvel
    rhythm beacon parade wander polish serene gentle bright sunset dawned mellow
    legend bridge timber orchid simple circle banana better cuddle sunray sentry
    safely health wonder stable lovely meadow saddle
  ].uniq.freeze

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

  # Public class method so other code (backfills, tasks) can reuse the same generator
  def self.generate_user_pass
    WORDLIST.sample
  end

  private

  # Ensure a 6-letter lowercase `user_pass` is set for every new user
  # Retries a few times to avoid collisions
  def ensure_user_pass
    # Use [] accessor to avoid calling undefined methods if attribute methods
    # are not yet generated (prevents NameError in some boot/load contexts)
    return unless self[:user_pass].blank?

    max_attempts = 10
    attempts = 0

    loop do
      candidate = self.class.generate_user_pass
      unless User.exists?(user_pass: candidate)
        # write_attribute / []= avoids relying on dynamic method generation
        self[:user_pass] = candidate
        break
      end

      attempts += 1
      next unless attempts >= max_attempts

      # Fallback: include random suffix if unique candidate not found
      suffix = SecureRandom.random_number(90) + 10 # two digits 10..99
      self[:user_pass] = "#{self.class.generate_user_pass}#{suffix}"
      break
    end
  end
end
