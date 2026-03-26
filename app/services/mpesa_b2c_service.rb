require 'net/http'
require 'base64'
require 'json'

class MpesaB2cService
  SANDBOX_BASE_URL = 'https://sandbox.safaricom.co.ke'.freeze
  PRODUCTION_BASE_URL = 'https://api.safaricom.co.ke'.freeze

  def initialize
    @consumer_key = ENV.fetch('MPESA_CONSUMER_KEY')
    @consumer_secret = ENV.fetch('MPESA_CONSUMER_SECRET')
    @initiator_name = ENV.fetch('MPESA_INITIATOR_NAME', 'testapi')
    @passkey = ENV.fetch('MPESA_PASSKEY')
    @party_a = ENV.fetch('MPESA_PARTY_A', '600984') # B2C shortcode
    @callback_base = ENV.fetch('MPESA_CALLBACK_BASE_URL') # e.g. https://abc123.ngrok.io
    @environment = ENV.fetch('MPESA_ENVIRONMENT', 'sandbox')
  end

  # Initiate a B2C payment.
  #
  # @param amount         [Numeric] Amount to disburse (integers only — M-Pesa rejects decimals)
  # @param phone_number   [String]  Recipient phone (any format; normalised internally)
  # @param transaction_id [String]  Our internal transaction_id (used as originator ref)
  # @param remarks        [String]  Free-text description sent to Safaricom (≤100 chars)
  # @param occasion       [String]  Optional extra context (≤100 chars)
  #
  # @return [Hash] { success:, conversation_id:, originator_conversation_id: } on success
  #               { success: false, error: } on failure
  def pay(amount:, phone_number:, transaction_id:, remarks: 'Payment', occasion: '')
    token = fetch_access_token
    return { success: false, error: 'Failed to obtain M-Pesa access token' } unless token

    phone = normalize_phone(phone_number)
    timestamp = generate_timestamp
    originator_id = "MELPAY-#{transaction_id}-#{Time.now.to_i}"

    payload = {
      OriginatorConversationID: originator_id,
      InitiatorName: @initiator_name,
      SecurityCredential: generate_password(timestamp),
      CommandID: 'BusinessPayment',
      Amount: amount.to_i,
      PartyA: @party_a,
      PartyB: phone,
      Remarks: remarks.to_s.truncate(100),
      Timestamp: timestamp,
      QueueTimeOutURL: "#{@callback_base}/mpesa/b2c/timeout",
      ResultURL: "#{@callback_base}/mpesa/b2c/result",
      Occasion: occasion.to_s.truncate(100)
    }

    response = post_json("#{base_url}/mpesa/b2c/v1/paymentrequest", payload, token)

    if response['ResponseCode'] == '0'
      {
        success: true,
        conversation_id: response['ConversationID'],
        originator_conversation_id: response['OriginatorConversationID'],
        response_description: response['ResponseDescription']
      }
    else
      {
        success: false,
        error: response['ResponseDescription'] || response['errorMessage'] || 'Unknown M-Pesa error',
        raw: response
      }
    end
  rescue KeyError => e
    Rails.logger.error "[MpesaB2cService] Missing env var: #{e.message}"
    { success: false, error: "Configuration error: #{e.message}" }
  rescue StandardError => e
    Rails.logger.error "[MpesaB2cService] #{e.class}: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # ── OAuth ─────────────────────────────────────────────────────────────────

  def fetch_access_token
    uri = URI("#{base_url}/oauth/v1/generate?grant_type=client_credentials")
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(@consumer_key, @consumer_secret)

    resp = http(uri).request(req)
    JSON.parse(resp.body)['access_token']
  rescue StandardError => e
    Rails.logger.error "[MpesaB2cService] OAuth error: #{e.message}"
    nil
  end

  # ── Password (passkey-based) ───────────────────────────────────────────────

  # Generates the SecurityCredential using the same pattern as STK Push:
  #   Base64(ShortCode + Passkey + Timestamp)
  def generate_password(timestamp)
    Base64.strict_encode64("#{@party_a}#{@passkey}#{timestamp}")
  end

  def generate_timestamp
    Time.now.strftime('%Y%m%d%H%M%S')
  end

  # ── HTTP helpers ──────────────────────────────────────────────────────────

  def post_json(url, payload, token)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json',
                                   'Authorization' => "Bearer #{token}")
    req.body = payload.to_json
    resp = http(uri).request(req)
    JSON.parse(resp.body)
  end

  def http(uri)
    Net::HTTP.new(uri.host, uri.port).tap do |h|
      h.use_ssl = true
      h.read_timeout = 30
      h.open_timeout = 10
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Normalises Kenyan phone numbers to 2547XXXXXXXX format.
  def normalize_phone(phone)
    digits = phone.to_s.gsub(/\D/, '')
    if digits.start_with?('254')
      digits
    elsif digits.start_with?('0')
      "254#{digits[1..]}"
    else
      "254#{digits}"
    end
  end

  def base_url
    sandbox? ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
  end

  def sandbox?
    @environment == 'sandbox'
  end
end
