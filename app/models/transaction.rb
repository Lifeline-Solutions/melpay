class Transaction < ApplicationRecord
  has_paper_trail
  belongs_to :home, optional: true
  belongs_to :client, optional: true
  belongs_to :user, optional: true
  belongs_to :previous_transaction, class_name: 'Transaction', foreign_key: 'previous_transaction_id', optional: true
  has_many :revised_transactions, class_name: 'Transaction', foreign_key: 'previous_transaction_id', dependent: :nullify

  STATUSES = %w[pending success failed].freeze

  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status, on: :create

  # Prevent direct updates to existing transactions
  before_update :prevent_direct_updates

  scope :pending, -> { where(status: 'pending') }
  scope :success, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failed') }
  scope :latest, -> { where(is_latest: true) }

  # Get all versions of this transaction (audit trail)
  def transaction_history
    history = []
    current = self

    # Go backwards through the chain
    while current.present?
      history.unshift(current)
      current = current.previous_transaction
    end

    history
  end

  # Create a new version of this transaction with updated attributes
  def create_revision(new_attributes)
    # Mark current transaction as not latest
    update_column(:is_latest, false)

    # Create new transaction record with the changes
    self.class.new(new_attributes.merge(
                     previous_transaction_id: id,
                     is_latest: true
                   ))
  end

  private

  def set_default_status
    self.status ||= 'pending'
  end

  MPESA_TRACKING_COLUMNS = %w[
    mpesa_conversation_id
    mpesa_originator_conversation_id
    mpesa_result_code
    mpesa_result_desc
    mpesa_transaction_receipt
  ].freeze

  def prevent_direct_updates
    # Allow updating the audit-trail flag and M-Pesa tracking columns (written by callbacks)
    allowed = %w[is_latest] + MPESA_TRACKING_COLUMNS
    return true if (changes.keys - allowed).empty?

    errors.add(:base, 'Transactions cannot be edited directly. Create a new revision instead.')
    throw(:abort)
  end
end
