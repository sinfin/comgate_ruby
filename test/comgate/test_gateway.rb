# frozen_string_literal: true

require "test_helper"

module Comgate
  class TestGateway < Minitest::Test
    include MethodInvokingMatchersHelper

    def test_initialization
      gateway = Comgate::Gateway.new(gateway_options)

      assert_equal gateway_options[:merchant_gateway_id], gateway.options[:merchant_gateway_id]
      assert gateway.test_calls_used?
    end

    def test_create_single_payment_on_frontend # rubocop:disable Metrics/AbcSize
      # If the payment is created through redirection (aka Frontend; the prepareOnly parameter is “false”),
      # then the payment gateway server directly redirects the Payer to the appropriate URL
      # or displays an error message.
      payment_params = minimal_payment_params
      expected_url = "https://payments.comgate.cz/v1.0/create"
      expected_payload = {
        curr: payment_params[:payment][:currency],
        email: payment_params[:payer][:email],
        label: payment_params[:payment][:label],
        merchant: gateway_options[:merchant_gateway_id],
        method: payment_params[:payment][:method],
        prepareOnly: false,
        price: payment_params[:payment][:price_in_cents],
        refId: payment_params[:payment][:reference_id],
        secret: nil
      }
      result = Comgate::ApiCaller::ResultHash.new(code: 302,
                                                  response_hash: {
                                                    headers: {
                                                      redirect_to: "https://payments.comgate.cz/relative/path"
                                                    }
                                                  })

      result = expect_method_called_on(object: Comgate::ApiCaller,
                                       method: :call,
                                       args: [],
                                       kwargs: { url: expected_url, payload: expected_payload, test_call: true },
                                       return_value: successful_service_stub(result)) do
        gateway.create_payment(payment_params)
      end

      assert_equal 302, result.code
      assert result.redirect?
      assert_equal "https://payments.comgate.cz/relative/path", result.redirect_to
    end

    # reccuring payments
    def test_create_single_payment_on_backend # rubocop:disable Metrics/AbcSize
      # The payment gateway server responds only if the payment is created in a background (prepareOnly=true).
      payment_params = minimal_payment_params
      payment_params[:payment][:at_background] = true

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
        secret: nil
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
        gateway.create_payment(payment_params)
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
        test_calls: true
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
                   method: "ALL",
                   at_background: false }
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
                   at_background: true, # always true!
                   background_secret: "hgfmkcslů",
                   init_payment_id: "dadasdaewvcxb" }
      }
    end

    def maximal_payment_params
      minimal_payment_params.deep_merge({
                                          payer: { phone: "+420777888999" },
                                          merchant: { target_shop_account: "12345678/1234" }, # gateway variable
                                          payment: { apple_pay_payload: "x",
                                                     dynamic_expiration: true,
                                                     expiration_time: "10h",
                                                     init_reccuring_payments: true,
                                                     product_name: "Usefull things",
                                                     preauthorization: false,
                                                     verification_payment: true },
                                          options: {
                                            country_code: "DE",
                                            embedded_iframe: false, # redirection after payment  # gateway variable
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
