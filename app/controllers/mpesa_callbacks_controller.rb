class MpesaCallbacksController < ApplicationController
  # Safaricom POSTs directly — no session/CSRF.
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :require_2fa, raise: false

  # POST /mpesa/b2c/result
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

  # POST /mpesa/b2c/timeout
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
