require 'ipaddr'

class MpesaCallbacksController < ApplicationController
  # Safaricom POSTs directly — no session/CSRF, and Daraja does not sign callbacks,
  # so the :token path segment and (optional) IP allowlist below are the only auth we get.
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :require_2fa, raise: false

  before_action :verify_callback_token
  before_action :verify_callback_ip

  # POST /mpesa/b2c/result/:token
  # Safaricom fires this once the B2C payment settles (success or failure).
  def b2c_result
    result = parsed_result
    return head :bad_request if result.nil?

    conversation_id = result['ConversationID']
    originator_conversation_id = result['OriginatorConversationID']
    result_code = result['ResultCode'].to_i
    result_desc = result['ResultDesc'].to_s

    receipt = extract_result_param(result, 'TransactionReceipt')

    transaction = find_transaction(conversation_id, originator_conversation_id)

    if transaction
      transaction.update_columns(
        mpesa_result_code: result_code,
        mpesa_result_desc: result_desc,
        mpesa_transaction_receipt: receipt
      )

      if result_code.zero?
        Rails.logger.info "[MpesaCallback] B2C success — txn #{transaction.transaction_id}, receipt #{receipt}"
      else
        Rails.logger.warn "[MpesaCallback] B2C failed — txn #{transaction.transaction_id}, code #{result_code}: #{result_desc}"
      end
    else
      Rails.logger.warn "[MpesaCallback] No transaction found for ConversationID=#{conversation_id} / OriginatorConversationID=#{originator_conversation_id}"
    end

    render json: { ResultCode: 0, ResultDesc: 'Accepted' }
  end

  # POST /mpesa/b2c/timeout/:token
  def b2c_timeout
    result = parsed_result
    return head :bad_request if result.nil?

    conversation_id = result['ConversationID']
    originator_conversation_id = result['OriginatorConversationID']

    transaction = find_transaction(conversation_id, originator_conversation_id)

    if transaction
      transaction.update_columns(
        mpesa_result_code: -1,
        mpesa_result_desc: 'Timeout — no response received from M-Pesa within the timeout window'
      )
      Rails.logger.warn "[MpesaCallback] B2C timeout — txn #{transaction&.transaction_id}"
    end

    render json: { ResultCode: 0, ResultDesc: 'Accepted' }
  end

  private

  # MPESA_CALLBACK_TOKEN must match the :token segment configured on the ResultURL/
  # QueueTimeOutURL sent to Safaricom (see MpesaB2cService). Required — refuses to boot
  # requests to this controller if unset, rather than silently accepting any token.
  def verify_callback_token
    expected = ENV.fetch('MPESA_CALLBACK_TOKEN')
    return if ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, expected)

    Rails.logger.warn "[MpesaCallback] Rejected — bad callback token from #{request.remote_ip}"
    head :unauthorized
  end

  # Optional hardening layer: only enforced if MPESA_CALLBACK_IP_ALLOWLIST is set.
  # Comma-separated list of IPs/CIDR ranges, e.g. Safaricom's published Daraja egress ranges.
  # Left opt-in because we don't want to hardcode IPs we haven't verified against the
  # current Daraja documentation for this account's environment.
  def verify_callback_ip
    allowlist = ENV['MPESA_CALLBACK_IP_ALLOWLIST'].to_s.split(',').map(&:strip).reject(&:blank?)
    return if allowlist.empty?

    remote_ip = IPAddr.new(request.remote_ip)
    return if allowlist.any? { |range| IPAddr.new(range).include?(remote_ip) }

    Rails.logger.warn "[MpesaCallback] Rejected — IP #{request.remote_ip} not in allowlist"
    head :forbidden
  end

  def parsed_result
    body = request.body.read
    data = JSON.parse(body)
    data['Result']
  rescue JSON::ParserError => e
    Rails.logger.error "[MpesaCallback] Invalid JSON body: #{e.message}"
    nil
  end

  def find_transaction(conversation_id, originator_conversation_id)
    Transaction.find_by(mpesa_conversation_id: conversation_id) ||
      Transaction.find_by(mpesa_originator_conversation_id: originator_conversation_id)
  end

  def extract_result_param(result, key)
    params_array = result.dig('ResultParameters', 'ResultParameter')
    return nil unless params_array.is_a?(Array)

    params_array.find { |p| p['Key'] == key }&.dig('Value')
  end
end
