class Client < ApplicationRecord
  include ActionView::Helpers::NumberHelper

  has_many :users, dependent: :nullify

  STATUSES = %w[pending approved rejected].freeze

  validates :name, :email, presence: true
  validates :kyc_status, inclusion: { in: STATUSES }

  # Existing validation for percentage rates
  validates :custom_interest_rate,
            numericality: {
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 100
            },
            allow_nil: true

  # New validations for fixed commissions
  validates :fixed_commission_amount,
            numericality: {
              greater_than_or_equal_to: 0
            },
            allow_nil: true
  validates :commission_type,
            inclusion: { in: %w[percentage fixed] },
            allow_nil: true

  before_validation :set_default_kyc_status, on: :create
  before_validation :clean_commission_fields

  # Existing methods
  def kyc_approved?
    kyc_status == 'approved'
  end

  def name_with_current_rate
    "#{name} (Current: #{applied_commission_display})"
  end

  def rate_type
    custom_interest_rate.present? ? 'Custom' : 'Global'
  end

  # NEW METHODS FOR COMMISSION FUNCTIONALITY

  # Determine if client uses percentage or fixed commission
  def percentage?
    commission_type.nil? ? SystemSetting.instance.percentage? : commission_type == 'percentage'
  end

  def fixed?
    commission_type.nil? ? SystemSetting.instance.fixed? : commission_type == 'fixed'
  end

  # Get the effective commission type (client's or global fallback)
  def effective_commission_type
    commission_type || SystemSetting.instance.commission_type
  end

  # Get the actual commission value to use in calculations
  def effective_commission_value
    if percentage?
      custom_interest_rate || SystemSetting.instance.global_interest_rate
    else
      fixed_commission_amount || SystemSetting.instance.fixed_commission_amount
    end
  end

  # Display formatted commission for UI
  def applied_commission_display
    if percentage?
      "#{effective_commission_value}%"
    else
      number_to_currency(effective_commission_value)
    end
  end

  # Backward compatibility - maintains existing behavior for interest rate display
  def applied_interest_rate
    percentage? ? effective_commission_value : nil
  end

  # Calculate commission for a transaction amount
  def calculate_commission(transaction_amount = 0)
    if percentage?
      transaction_amount * (effective_commission_value / 100.0)
    else
      effective_commission_value
    end
  end

  # Reset client to use global settings
  def reset_to_global_commission
    update(
      commission_type: nil,
      custom_interest_rate: nil,
      fixed_commission_amount: nil
    )
  end

  private

  def clean_commission_fields
    # Convert empty strings to nil for commission fields
    self.commission_type = nil if commission_type.blank?
    self.custom_interest_rate = nil if custom_interest_rate.blank?
    self.fixed_commission_amount = nil if fixed_commission_amount.blank?
  end

  def set_default_kyc_status
    self.kyc_status ||= 'pending'
  end
end
