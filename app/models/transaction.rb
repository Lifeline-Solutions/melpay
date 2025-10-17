class Transaction < ApplicationRecord
  belongs_to :home, optional: true
  belongs_to :client, optional: true
  belongs_to :user, optional: true

  STATUSES = %w[pending success failed].freeze

  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status, on: :create

  # Prevent re-processing of successful transactions
  validate :cannot_change_successful_transaction, on: :update

  scope :pending, -> { where(status: 'pending') }
  scope :success, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failed') }

  private

  def set_default_status
    self.status ||= 'pending'
  end

  def cannot_change_successful_transaction
    return unless status_was == 'success' && status_changed?

    errors.add(:status, 'cannot be changed once transaction is successful')
  end
end
