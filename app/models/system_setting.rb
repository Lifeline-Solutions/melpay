class SystemSetting < ApplicationRecord
  validates :global_interest_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Returns the singleton instance
  def self.instance
    first_or_create!(global_interest_rate: 2.0)
  end
end