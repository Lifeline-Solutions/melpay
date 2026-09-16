require 'test_helper'

class MpesaCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = 'test-callback-token'
    ENV['MPESA_CALLBACK_TOKEN'] = @token
  end

  teardown do
    ENV.delete('MPESA_CALLBACK_TOKEN')
    ENV.delete('MPESA_CALLBACK_IP_ALLOWLIST')
  end

  test 'rejects a result callback with the wrong token' do
    post mpesa_b2c_result_path(token: 'wrong-token'), params: sample_result_body, as: :json

    assert_response :unauthorized
  end

  test 'accepts a result callback with the correct token and no matching transaction' do
    post mpesa_b2c_result_path(token: @token), params: sample_result_body, as: :json

    assert_response :success
  end

  test 'rejects a callback from an IP outside the configured allowlist' do
    ENV['MPESA_CALLBACK_IP_ALLOWLIST'] = '10.0.0.0/8'

    post mpesa_b2c_result_path(token: @token), params: sample_result_body, as: :json

    assert_response :forbidden
  end

  test 'accepts a callback from an IP inside the configured allowlist' do
    ENV['MPESA_CALLBACK_IP_ALLOWLIST'] = '127.0.0.1/32'

    post mpesa_b2c_result_path(token: @token), params: sample_result_body, as: :json

    assert_response :success
  end

  private

  def sample_result_body
    {
      Result: {
        ConversationID: 'AG_00000000_0000000000',
        OriginatorConversationID: 'MELPAY-none-0',
        ResultCode: 0,
        ResultDesc: 'Success'
      }
    }
  end
end
