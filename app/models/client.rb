class Client < ApplicationRecord
  has_many :accounts, dependent: :destroy
  has_many :users, dependent: :nullify

  STATUSES = %w[pending approved rejected].freeze

  validates :name, :email, presence: true
  validates :kyc_status, inclusion: { in: STATUSES }
  # Validation to ensure percentage is numeric and within 0–100
  validates :custom_interest_rate,
            numericality: {
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 100
            },
            allow_nil: true

  before_validation :set_default_kyc_status, on: :create

  def kyc_approved?
    kyc_status == 'approved'
  end

  def name_with_current_rate
    "#{name} (Current: #{applied_interest_rate}%)"
  end

  def applied_interest_rate
    custom_interest_rate || SystemSetting.instance.global_interest_rate
  end

  def rate_type
    custom_interest_rate.present? ? 'Custom' : 'Global'
  end

  private

  def set_default_kyc_status
    self.kyc_status ||= 'pending'
  end
end
