# frozen_string_literal: true

require "test_helper"
require "base64"

module Comgate
  class TestGateway < Minitest::Test
    include MethodInvokingMatchersHelper

    def test_initialization
      gateway = Comgate::Gateway.new(gateway_options)

      assert_equal gateway_options[:merchant_gateway_id], gateway.options[:merchant_gateway_id]
      assert gateway.test_calls_used?
    end

    def test_create_single_payment_with_minimal_data # rubocop:disable Metrics/AbcSize
      # The payment gateway server responds only if the payment is created in a background (prepareOnly=true).
      payment_params = minimal_payment_params

      expected_url = "https://payments.comgate.cz/v1.0/create"
      expected_payload = {
        curr: payment_params[:payment][:currency],
        email: payment_params[:payer][:email],
        label: payment_params[:payment][:label],
        merchant: gateway_options[:merchant_gateway_id],
        method: payment_params[:payment][:method],
        prepareOnly: true,
        price: payment_params[:payment][:price_in_cents],
        refId: payment_params[:payment][:reference_id],
        secret: gateway_options[:secret]
      }
      response_hash = { code: 0,
                        message: "OK",
                        transId: "AB12-CD34-EF56",
                        redirect: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }
      result = Comgate::ApiCaller::ResultHash.new(code: 200,
                                                  response_hash: response_hash)

      result = expect_method_called_on(object: Comgate::ApiCaller,
                                       method: :call,
                                       args: [],
                                       kwargs: { url: expected_url, payload: expected_payload, test_call: true },
                                       return_value: successful_service_stub(result)) do
        gateway.start_transaction(payment_params)
      end

      assert !result.redirect?
      assert_equal 200, result.code
      assert_equal(response_hash, result.response_hash)
    end

    def test_create_single_payment_with_maximal_data # rubocop:disable Metrics/AbcSize
      # The payment gateway server responds only if the payment is created in a background (prepareOnly=true).
      payment_params = maximal_payment_params.merge(test: false)

      expected_url = "https://payments.comgate.cz/v1.0/create"
      expected_payload = {
        curr: payment_params[:payment][:currency],
        email: payment_params[:payer][:email],
        label: payment_params[:payment][:label],
        merchant: gateway_options[:merchant_gateway_id],
        method: payment_params[:payment][:method],
        prepareOnly: true,
        price: payment_params[:payment][:price_in_cents],
        refId: payment_params[:payment][:reference_id],
        secret: gateway_options[:secret],
        account: payment_params[:merchant][:target_shop_account],
        applePayPayload: Base64.encode64(payment_params[:payment][:apple_pay_payload]),
        country: payment_params[:options][:country_code],
        dynamicExpiration: payment_params[:payment][:dynamic_expiration],
        expirationTime: payment_params[:payment][:expiration_time],
        name: payment_params[:payment][:product_name],
        lang: payment_params[:options][:language_code],
        phone: payment_params[:payer][:phone]
      }

      response_hash = { code: 0,
                        message: "OK",
                        transId: "AB12-CD34-EF56",
                        redirect: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }
      result = Comgate::ApiCaller::ResultHash.new(code: 200,
                                                  response_hash: response_hash)

      result = expect_method_called_on(object: Comgate::ApiCaller,
                                       method: :call,
                                       args: [],
                                       kwargs: { url: expected_url, payload: expected_payload, test_call: false },
                                       return_value: successful_service_stub(result)) do
        gateway.start_transaction(payment_params)
      end

      assert !result.redirect?
      assert_equal 200, result.code
      assert_equal(response_hash, result.response_hash)
    end

    def test_create_reccuring_payment; end

    def test_create_verification_payment; end

    def test_create_preauthorizated_payment; end

    def test_cancel_preauthorizated_payment; end

    def test_refund_payment
      # partial or whole
    end

    def test_cancel_payment; end

    def test_get_payment_status; end

    def test_get_available_payment_methods; end

    def test_get_transfers_list; end

    private

    def gateway
      @gateway ||= Comgate::Gateway.new(gateway_options)
    end

    def gateway_options
      {
        merchant_gateway_id: "some_id_from_comgate",
        test_calls: true,
        secret: "Psst!ItIsPrivate!"
      }
    end

    def minimal_payment_params
      {
        payer: { email: "joh@eaxample.com" },
        # merchant: { gateway_id: "sdasdsadad546dfa" }, # gateway variable
        payment: { currency: "CZK",
                   price_in_cents: 100, # 1 CZK
                   label: "#2023-0123",
                   reference_id: "#2023-0123",
                   method: "ALL" }
      }
    end

    def minimal_reccuring_payment_params
      {
        payer: { email: "joh@eaxample.com" },
        merchant: { gateway_id: "sdasdsadad546dfa" }, # gateway variable
        payment: { currency: "CZK",
                   price_in_cents: 100, # 1 CZK
                   label: "#2023-0123-4",
                   reference_id: "#2023-0123",
                   init_payment_id: "dadasdaewvcxb" }
      }
    end

    def maximal_payment_params
      minimal_payment_params.deep_merge({
                                          payer: { phone: "+420777888999" },
                                          merchant: { target_shop_account: "12345678/1234" }, # gateway variable
                                          payment: { apple_pay_payload: "apple pay payload",
                                                     dynamic_expiration: false,
                                                     expiration_time: "10h",
                                                     # init_reccuring_payments: true,
                                                     product_name: "Usefull things" },
                                          # preauthorization: false,
                                          # verification_payment: true,
                                          options: {
                                            country_code: "DE",
                                            # embedded_iframe: false, # redirection after payment  # gateway variable
                                            language_code: "sk"
                                          },
                                          test: true
                                        })
    end

    def maximal_reccuring_payment_params
      minimal_reccuring_payment_params.deep_merge({
                                                    payer: { phone: "+420777888999" },
                                                    merchant: { target_shop_account: "12345678/1234" },
                                                    payment: { apple_pay_payload: "x",
                                                               dynamic_expiration: true,
                                                               expiration_time: "10h",
                                                               init_reccuring_payments: true,
                                                               product_name: "Usefull things",
                                                               preauthorization: false,
                                                               verification_payment: true },
                                                    options: {
                                                      country_code: "DE",
                                                      embedded_iframe: false, # redirection after payment
                                                      lang_code: "sk"
                                                    },
                                                    test: true
                                                  })
    end

    ServiceStubStruct = Struct.new(:success?, :errors, :result, keyword_init: true)
    def successful_service_stub(result)
      ServiceStubStruct.new(success?: true,
                            errors: {},
                            result: result)
    end

    # GOPAY params for inspiration
    #     { payer: { allowed_payment_instruments: ["PAYMENT_CARD"],
    #                           contact: { first_name: 'John',
    #                                      last_name: 'Doe',
    #                                      email: 'john@example.com',
    #                                      phone: } },
    #                  amount: 10000, # in cents
    #                  currency: 'CZK',
    #                  order_number: 'order-1',
    #                  order_description: 'foo',
    #                  lang: 'CS',
    #                  callback: { return_url: 'http://localhost',
    #                                           notification_url: 'http://localhost/2' } } }
    # let(:recurrence_params) { { recurrence: { recurrence_cycle: 'WEEK',
    #                                            recurrence_period: 10,
    #                                            recurrence_date_to: '2050-01-01' } } }

    # PATHS
    # 1.0/capturePreauth
    # https://payments.comgate.cz/v1.0/cancelPreauth
    # https://payments.comgate.cz/v1.0/recurring
    # https://payments.comgate.cz/v1.0/refund
    # https://payments.comgate.cz/v1.0/cancel
    # https://payments.comgate.cz/v1.0/status
    # https://payments.comgate.cz/v1.0/methods
    # https://payments.comgate.cz/v1.0/transferList
  end
end
