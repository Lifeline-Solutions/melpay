class Home < ApplicationRecord
  belongs_to :client, optional: true
  belongs_to :user
  has_one_attached :document

  validate :acceptable_document
  before_create :generate_unique_id

  # Generate unique, progressive home ID for this home record
  def generate_unique_id
    return if unique_id.present? # Don't regenerate if already set

    prefix = if client&.name.present?
               client.name.split.first.upcase
             else
               'DEFAULT'
             end

    # Find the highest home ID number for this client
    max_number = 0

    Home.where(client_id: client&.id)
      .where('unique_id LIKE ?', "#{prefix}-%")
      .pluck(:unique_id)
      .each do |uid|
      if uid =~ /^#{Regexp.escape(prefix)}-(\d+)$/
        number = Regexp.last_match(1).to_i
        max_number = number if number > max_number
      end
    end

    self.unique_id = "#{prefix}-#{(max_number + 1).to_s.rjust(4, '0')}"
  end

  # Generate unique, progressive transaction IDs across all forms for a client
  # Format: CLIENT_NAME-XXXX (e.g., Melpay-0001, Solidity-0002, etc.)
  # IDs are unique per client and never duplicated
  def self.next_transaction_id(client)
    client_prefix = if client&.name.present?
                      client.name.split.first.upcase
                    else
                      'DEFAULT'
                    end

    # Find the highest transaction ID number for this client across all homes
    max_number = 0

    Home.where(client_id: client&.id).find_each do |home|
      next unless home.processed_deposits.is_a?(Array)

      home.processed_deposits.each do |deposit|
        if deposit['transaction_id'] =~ /^#{Regexp.escape(client_prefix)}-(\d+)$/
          number = Regexp.last_match(1).to_i
          max_number = number if number > max_number
        end
      end
    end

    "#{client_prefix}-#{(max_number + 1).to_s.rjust(4, '0')}"
  end

  # Check if a transaction ID already exists for a client
  def self.transaction_id_exists?(transaction_id, client_id)
    Home.where(client_id: client_id).find_each do |home|
      next unless home.processed_deposits.is_a?(Array)

      return true if home.processed_deposits.any? { |d| d['transaction_id'] == transaction_id }
    end

    false
  end

  private

  def acceptable_document
    return unless document.attached?

    acceptable_types = %w[
      application/vnd.ms-excel
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      text/csv
      text/plain
    ]

    return if document.content_type.in?(acceptable_types)

    errors.add(:document, 'must be a CSV or Excel file (.csv, .xls, or .xlsx)')
  end
end
