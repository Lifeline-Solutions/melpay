class SystemSetting < ApplicationRecord
  validates :global_interest_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :fixed_commission_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :commission_type, inclusion: { in: %w[percentage fixed] }
  
  def self.instance
    first_or_create!(
      global_interest_rate: 2.0,
      commission_type: 'percentage'
    )
  end
  
  def percentage?
    commission_type == 'percentage'
  end
  
  def fixed?
    commission_type == 'fixed'
  end
end
