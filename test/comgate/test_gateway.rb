# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"

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

      expectations = { call_url: "https://payments.comgate.cz/v1.0/create",
                       call_payload: { curr: payment_params[:payment][:currency],
                                       email: payment_params[:payer][:email],
                                       label: payment_params[:payment][:label],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       method: payment_params[:payment][:method],
                                       prepareOnly: true,
                                       price: payment_params[:payment][:price_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:secret] },
                       response_hash: { code: 0,
                                        message: "OK",
                                        transaction_id: "AB12-CD34-EF56",
                                        redirect: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_transaction(payment_params)
      end

      assert result.redirect?
      assert_equal(expectations[:response_hash], result.response_hash)
      assert_equal expectations[:response_hash][:redirect], result.redirect_to
      assert !result.response_hash[:transaction_id].nil?
    end

    def test_create_single_payment_with_maximal_data # rubocop:disable Metrics/AbcSize
      # The payment gateway server responds only if the payment is created in a background (prepareOnly=true).
      payment_params = maximal_payment_params.merge(test: false)

      expectations = { call_url: "https://payments.comgate.cz/v1.0/create",
                       call_payload: { curr: payment_params[:payment][:currency],
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
                                       phone: payment_params[:payer][:phone] },
                       response_hash: { code: 0,
                                        message: "OK",
                                        transaction_id: "AB12-CD34-EF56",
                                        redirect: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: false }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_transaction(payment_params)
      end

      assert result.redirect?
      assert_equal(expectations[:response_hash], result.response_hash)
      assert_equal expectations[:response_hash][:redirect], result.redirect_to
      assert !result.response_hash[:transaction_id].nil?
    end

    def test_process_comgate_state_change_request
      skip
    end

    def test_create_reccuring_payments # rubocop:disable Metrics/AbcSize
      payment_params = minimal_payment_params

      # inital is common payment with `initRecurring` tag
      expectations = { call_url: "https://payments.comgate.cz/v1.0/create",
                       call_payload: { curr: payment_params[:payment][:currency],
                                       email: payment_params[:payer][:email],
                                       label: payment_params[:payment][:label],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       method: payment_params[:payment][:method],
                                       prepareOnly: true,
                                       initRecurring: true,
                                       price: payment_params[:payment][:price_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:secret] },
                       response_hash: { code: 0,
                                        message: "OK",
                                        transaction_id: "AB12-CD34-EF56",
                                        redirect: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_recurring_transaction(payment_params)
      end

      assert result.redirect?
      assert_equal(expectations[:response_hash], result.response_hash)
      assert_equal expectations[:response_hash][:redirect], result.redirect_to

      transaction_id = result.response_hash[:transaction_id]
      assert !transaction_id.nil?

      # next payment is on background
      new_payment_params = payment_params
      new_payment_params[:payment][:price_in_cents] = 4_200

      expectations = { call_url: "https://payments.comgate.cz/v1.0/recurring",
                       call_payload: { curr: payment_params[:payment][:currency],
                                       email: payment_params[:payer][:email],
                                       label: payment_params[:payment][:label],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       method: payment_params[:payment][:method],
                                       prepareOnly: true,
                                       initRecurringId: transaction_id,
                                       price: payment_params[:payment][:price_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:secret] },
                       response_hash: { code: 0,
                                        message: "OK",
                                        transaction_id: "XB11-CD34-EF56" },
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.repeat_recurring_transaction(transaction_id: transaction_id, payment_data: new_payment_params)
      end

      assert !result.redirect?
      assert_nil result.redirect_to
      assert_equal(expectations[:response_hash], result.response_hash)

      new_transaction_id = result.response_hash[:transaction_id]
      assert !new_transaction_id.nil?
      assert transaction_id != new_transaction_id
    end

    def test_create_verification_payment # rubocop:disable Metrics/AbcSize
      payment_params = minimal_payment_params

      expectations = { call_url: "https://payments.comgate.cz/v1.0/create",
                       call_payload: { curr: payment_params[:payment][:currency],
                                       email: payment_params[:payer][:email],
                                       label: payment_params[:payment][:label],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       method: payment_params[:payment][:method],
                                       prepareOnly: true,
                                       verification: true,
                                       price: payment_params[:payment][:price_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:secret] },
                       response_hash: { code: 0,
                                        message: "OK",
                                        transaction_id: "AB12-CD34-EF56",
                                        redirect: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_verfication_transaction(payment_params)
      end

      assert result.redirect?
      assert_equal(expectations[:response_hash], result.response_hash)
      assert_equal expectations[:response_hash][:redirect], result.redirect_to
      assert !result.response_hash[:transaction_id].nil?
    end

    def test_create_preauthorized_payment = skip
    def test_confirm_preauthorized_payment = skip
    def test_cancel_preauthorized_payment = skip

    def test_refund_payment
      # partial or whole
    end

    def test_cancel_payment = skip

    def test_get_payment_state
      transaction_id = "1234-4567-89AB"

      expectations = { call_url: "https://payments.comgate.cz/v1.0/status",
                       call_payload: { merchant: gateway_options[:merchant_gateway_id],
                                       transId: transaction_id,
                                       secret: gateway_options[:secret] },

                       response_hash: { code: 0,
                                        message: "OK",
                                        merchant: gateway_options[:merchant_gateway_id].to_s,
                                        test: "false",
                                        price: "12900",
                                        curr: "CZK",
                                        label: "Automaticky obnovované předplatné pro ABC",
                                        refId: "62bdf52e1fdcdd5f02d",
                                        method: "CARD_CZ_CSOB_2",
                                        email: "payer1@gmail.com",
                                        name: "product name ABC",
                                        transId: "3IX8-NZ9I-KDTO",
                                        secret: "other_secret",
                                        status: "PAID",
                                        fee: "unknown",
                                        vs: "739689656",
                                        payer_acc: "account_num",
                                        payerAcc: "account_num_again",
                                        payer_name: "me",
                                        payerName: "me again!",
                                        headers: {} },
                       test_call: false }

      result = expect_successful_api_call_with(expectations) do
        gateway.check_state(transaction_id: transaction_id)
      end

      expected_gateway_response_hash = {
        code: 0,
        message: "OK",
        merchant: "some_id_from_comgate",
        test: "false",
        transaction_id: "3IX8-NZ9I-KDTO",
        status: "PAID",
        payment: {
          price_in_cents: "12900",
          currency: "CZK",
          label: "Automaticky obnovované předplatné pro ABC",
          reference_id: "62bdf52e1fdcdd5f02d",
          method: "CARD_CZ_CSOB_2",
          product_name: "product name ABC",
          fee: "unknown",
          variable_symbol: "739689656"
        },
        payer: {
          email: "payer1@gmail.com",
          account_number: "account_num_again",
          account_name: "me again!"
        },
        headers: {}
      }
      assert !result.redirect?
      assert_nil result.redirect_to
      assert_equal expected_gateway_response_hash, result.response_hash
    end

    def test_get_available_payment_methods
      result_hash = { methods: [
        {
          id: "CARD_CZ_CSOB_2",
          name: "Platební karta",
          description: "On-line platba platební kartou.",
          logo: "https://payments.comgate.cz/assets/images/logos/CARD_CZ_CSOB_2.png?v=1.4"
        },
        {
          id: "APPLEPAY_REDIRECT",
          name: "Apple Pay",
          description: "On-line platba pomocí Apple Pay.",
          logo: "https://payments.comgate.cz/assets/images/logos/APPLEPAY_REDIRECT.png?v=1.4"
        },
        {
          id: "GOOGLEPAY_REDIRECT",
          name: "Google Pay",
          description: "On-line platba pomocí Google Pay.",
          logo: "https://payments.comgate.cz/assets/images/logos/GOOGLEPAY_REDIRECT.png?v=1.4"
        },
        {
          id: "LATER_TWISTO",
          name: "Twisto",
          description: "Twisto - Platba do 30 dnů",
          logo: "https://payments.comgate.cz/assets/images/logos/LATER_TWISTO.png?v=1.4"
        },
        {
          id: "PART_TWISTO",
          name: "Twisto Nákup na třetiny",
          description: "Bez navýšení, ve třech měsíčních splátkách",
          logo: "https://payments.comgate.cz/assets/images/logos/PART_TWISTO.png?v=1.4"
        },
        {
          id: "BANK_CZ_RB",
          name: "Raiffeisenbank",
          description: "On-line platba pro majitele účtu u Raiffeisenbank.",
          logo: "https://payments.comgate.cz/assets/images/logos/BANK_CZ_RB.png?v=1.4"
        },
        {
          id: "BANK_CZ_OTHER",
          name: "Ostatní banky",
          description: "Bankovní převod pro majitele účtu u jiné banky (CZ).",
          logo: "https://payments.comgate.cz/assets/images/logos/BANK_CZ_OTHER.png?v=1.4"
        }
      ] }

      params = { # same structure as for payments
        payment: { currency: "EUR" },
        options: { language_code: "sk",
                   country_code: "SK" }
      }

      full_params_expectations = {
        call_url: "https://payments.comgate.cz/v1.0/methods",
        call_payload: { lang: params[:options][:language_code],
                        curr: params[:payment][:currency],
                        country: params[:options][:country_code],
                        merchant: gateway_options[:merchant_gateway_id],
                        secret: gateway_options[:secret] },
        response_hash: result_hash,
        test_call: false
      }

      result = expect_successful_api_call_with(full_params_expectations) do
        gateway.allowed_payment_methods(params)
      end

      assert_equal result_hash, result.response_hash
    end

    def test_get_transfers_list = skip

    def test_raises_api_caller_errors # rubocop:disable Metrics/AbcSize
      payment_params = minimal_payment_params

      expectations = { call_url: "https://payments.comgate.cz/v1.0/create",
                       call_payload: { curr: payment_params[:payment][:currency],
                                       email: payment_params[:payer][:email],
                                       label: payment_params[:payment][:label],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       method: payment_params[:payment][:method],
                                       prepareOnly: true,
                                       verification: true,
                                       price: payment_params[:payment][:price_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:secret] },
                       response_hash: { code: 1309,
                                        message: "Nespravná cena" },
                       errors: { api: ["errr"] },
                       test_call: true }

      exception = expect_failed_api_call_with(expectations) do
        gateway.start_verfication_transaction(payment_params)
      end

      assert_equal RuntimeError, exception.class
      assert_equal expectations[:errors].to_s, exception.message
    end

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

    def expect_successful_api_call_with(expectations, &block)
      api_result = Comgate::ApiCaller::ResultHash.new(http_code: 200,
                                                      redirect_to: expectations[:response_hash][:redirect],
                                                      response_hash: expectations[:response_hash])

      result = expect_method_called_on(object: Comgate::ApiCaller,
                                       method: :call,
                                       args: [],
                                       kwargs: { url: expectations[:call_url],
                                                 payload: expectations[:call_payload],
                                                 test_call: expectations[:test_call] },
                                       return_value: service_stub(true, api_result, {}),
                                       &block)

      assert_equal 200, result.http_code
      result
    end

    def expect_failed_api_call_with(expectations, &block)
      api_result = Comgate::ApiCaller::ResultHash.new(http_code: 200,
                                                      response_hash: expectations[:response_hash])

      assert_raises "xxx" do
        expect_method_called_on(object: Comgate::ApiCaller,
                                method: :call,
                                args: [],
                                kwargs: { url: expectations[:call_url],
                                          payload: expectations[:call_payload],
                                          test_call: expectations[:test_call] },
                                return_value: service_stub(false, api_result, expectations[:errors]),
                                      &block)
      end
    end

    ServiceStubStruct = Struct.new(:success?, :errors, :result, keyword_init: true) do
      def failure?
        !success?
      end

      def failed?
        failure?
      end
    end

    def service_stub(success, result, errors)
      ServiceStubStruct.new(success?: success,
                            errors: errors,
                            result: result)
    end

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
