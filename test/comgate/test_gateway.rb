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
                                       price: payment_params[:payment][:amount_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "0",
                                        "message" => "OK",
                                        "transId" => "AB12-CD34-EF56",
                                        "redirect" => "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_transaction(payment_params)
      end

      assert result.redirect?
      expected_result_hash = { code: 0,
                               message: "OK",
                               transaction_id: expectations[:response_body]["transId"],
                               redirect_to: expectations[:response_body]["redirect"] }
      assert_equal expected_result_hash, result.hash
      assert_equal expected_result_hash[:redirect_to], result.redirect_to
      assert !result.hash[:transaction_id].nil?
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
                                       price: payment_params[:payment][:amount_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret],
                                       account: payment_params[:merchant][:target_shop_account],
                                       applePayPayload: Base64.encode64(payment_params[:payment][:apple_pay_payload]),
                                       country: payment_params[:options][:country_code],
                                       dynamicExpiration: payment_params[:payment][:dynamic_expiration],
                                       expirationTime: payment_params[:payment][:expiration_time],
                                       name: payment_params[:payment][:product_name],
                                       lang: payment_params[:options][:language_code],
                                       phone: payment_params[:payer][:phone] },
                       response_body: { "code" => "0",
                                        "message" => "OK",
                                        "transId" => "AB12-CD34-EF56",
                                        "redirect" => "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: false }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_transaction(payment_params)
      end

      expected_result_hash = { code: 0,
                               message: "OK",
                               transaction_id: expectations[:response_body]["transId"],
                               redirect_to: expectations[:response_body]["redirect"] }
      assert_equal expected_result_hash, result.hash
      assert_equal expected_result_hash[:redirect_to], result.redirect_to
      assert result.redirect?
      assert !result.hash[:transaction_id].nil?
    end

    def test_process_comgate_state_change_request
      mandatory_params = {
        "curr" => "CZK",
        "email" => "mail@me.at",
        "label" => "Beatles",
        "merchant" => "123456",
        "price" => "10000",
        "refId" => "20230302007",
        "secret" => "gx4q8OV3TJt6noJnfhjqJKyX3Z6Ych0y",
        "status" => "PAID",
        "test" => "true",
        "transId" => "AB12-CD34-EF56"
      }

      result = gateway.process_callback(mandatory_params)

      expected_result = {
        transaction_id: mandatory_params["transId"],
        state: :paid,
        test: true,
        merchant: { gateway_id: mandatory_params["merchant"] },
        payer: { email: "mail@me.at" },
        payment: { currency: "CZK",
                   label: "Beatles",
                   amount_in_cents: 10_000,
                   reference_id: "20230302007" }
      }
      expect(result.hash).to eql(expected_result)

      optional_params = {
        "account" => "accc", # ?
        "fee" => "3.42", # or  "unknown"
        "method" => "CARD_CZ_CSOB_2",
        "name" => "CD + book",
        "payerId" => "pid", # ?
        "payerName" => "payerName",
        "payer_name" => "payer_name",
        "phone" => "CALLING ELVIS",
        "payerAcc" => "payerAccount",
        "payer_acc" => "payer_account",
        "vs" => "673989665"
      }

      result = gateway.process_callback(mandatory_params.merge(optional_params))

      optional_expected_result = {
        merchant: { target_shop_account: optional_params["account"] },
        payer: { account_name: optional_params["payer_name"],
                 account_number: optional_params["payer_acc"],
                 id: optional_params["payerId"],
                 phone: optional_params["phone"] },
        payment: { fee: 3.42,
                   method: "CARD_CZ_CSOB_2",
                   product_name: "CD + book",
                   variable_symbol: 673_989_665 }
      }

      expect(result.hash).to eql(expected_result.deep_merge(optional_expected_result))
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
                                       price: payment_params[:payment][:amount_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "0",
                                        "message" => "OK",
                                        "transId" => "AB12-CD34-EF56",
                                        "redirect" => "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_recurring_transaction(payment_params)
      end

      expected_result_hash = { code: 0,
                               message: "OK",
                               transaction_id: expectations[:response_body]["transId"],
                               redirect_to: expectations[:response_body]["redirect"] }
      assert_equal expected_result_hash, result.hash
      assert_equal expected_result_hash[:redirect_to], result.redirect_to
      assert result.redirect?
      transaction_id = result.hash[:transaction_id]
      assert !transaction_id.nil?

      # next payment is on background
      new_payment_params = payment_params
      new_payment_params[:payment][:amount_in_cents] = 4_200
      new_payment_params[:transaction_id] = transaction_id

      expectations = { call_url: "https://payments.comgate.cz/v1.0/recurring",
                       call_payload: { curr: payment_params[:payment][:currency],
                                       email: payment_params[:payer][:email],
                                       label: payment_params[:payment][:label],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       method: payment_params[:payment][:method],
                                       prepareOnly: true,
                                       initRecurringId: transaction_id,
                                       price: payment_params[:payment][:amount_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "0",
                                        "message" => "OK",
                                        "transId" => "XB11-CD34-EF56" },
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.repeat_recurring_transaction(new_payment_params)
      end

      expected_result_hash = { code: 0,
                               message: "OK",
                               transaction_id: expectations[:response_body]["transId"] }
      assert_equal expected_result_hash, result.hash
      assert !result.redirect?
      assert_nil result.redirect_to

      new_transaction_id = result.hash[:transaction_id]
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
                                       price: payment_params[:payment][:amount_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "0",
                                        "message" => "OK",
                                        "transId" => "AB12-CD34-EF56",
                                        "redirect" => "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_verification_transaction(payment_params)
      end

      expected_result_hash = { code: 0,
                               message: "OK",
                               transaction_id: expectations[:response_body]["transId"],
                               redirect_to: expectations[:response_body]["redirect"] }
      assert_equal expected_result_hash, result.hash
      assert_equal expected_result_hash[:redirect_to], result.redirect_to
      assert result.redirect?
      assert !result.hash[:transaction_id].nil?
    end

    def test_create_preauthorized_payment # rubocop:disable Metrics/AbcSize
      payment_params = minimal_payment_params

      expectations = { call_url: "https://payments.comgate.cz/v1.0/create",
                       call_payload: { curr: payment_params[:payment][:currency],
                                       email: payment_params[:payer][:email],
                                       label: payment_params[:payment][:label],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       method: payment_params[:payment][:method],
                                       prepareOnly: true,
                                       preauth: true,
                                       price: payment_params[:payment][:amount_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "0",
                                        "message" => "OK",
                                        "transId" => "AB12-CD34-EF56",
                                        "redirect" => "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }, # rubocop:disable Layout/LineLength
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.start_preauthorized_transaction(payment_params)
      end

      expected_result_hash = { code: 0,
                               message: "OK",
                               transaction_id: expectations[:response_body]["transId"],
                               redirect_to: expectations[:response_body]["redirect"] }
      assert_equal expected_result_hash, result.hash
      assert_equal expected_result_hash[:redirect_to], result.redirect_to
      assert result.redirect?
      assert !result.hash[:transaction_id].nil?
    end

    def test_confirm_preauthorized_payment
      params = { transaction_id: "AB12-CD34-EF56", # preauthorized transtaction created in past
                 payment: { amount_in_cents: 200 } }
      confirm_expectations = { call_url: "https://payments.comgate.cz/v1.0/capturePreauth",
                               call_payload: { merchant: gateway_options[:merchant_gateway_id],
                                               amount: params[:payment][:amount_in_cents],
                                               transId: params[:transaction_id],
                                               secret: gateway_options[:client_secret] },
                               response_body: { "code" => "0",
                                                "message" => "OK" },
                               test_call: false }

      result = expect_successful_api_call_with(confirm_expectations) do
        gateway.confirm_preauthorized_transaction(params)
      end

      assert !result.redirect?
      assert_equal({ code: 0, message: "OK" }, result.hash)
    end

    def test_cancel_preauthorized_payment
      transaction_id = "AB12-CD34-EF56" # preauthorized transtaction created in past

      confirm_expectations = { call_url: "https://payments.comgate.cz/v1.0/cancelPreauth",
                               call_payload: { merchant: gateway_options[:merchant_gateway_id],
                                               transId: transaction_id,
                                               secret: gateway_options[:client_secret] },
                               response_body: { "code" => "0",
                                                "message" => "OK" },
                               test_call: false }

      result = expect_successful_api_call_with(confirm_expectations) do
        gateway.cancel_preauthorized_transaction(transaction_id: transaction_id)
      end

      assert !result.redirect?
      assert_equal({ code: 0, message: "OK" }, result.hash)
    end

    def test_refund_payment
      params = { payment: { currency: "CZK", # optional
                            amount_in_cents: 200, # 2 CZK
                            reference_id: "#2023-0123" }, # optional
                 transaction_id: "1234-abcd-5678" }

      expectations = { call_url: "https://payments.comgate.cz/v1.0/refund",
                       call_payload: { curr: params[:payment][:currency],
                                       transId: params[:transaction_id],
                                       amount: params[:payment][:amount_in_cents],
                                       merchant: gateway_options[:merchant_gateway_id],
                                       refId: params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "0",
                                        "message" => "OK" },
                       test_call: true }

      result = expect_successful_api_call_with(expectations) do
        gateway.refund_transaction(params)
      end

      assert !result.redirect?
      assert_equal({ code: 0, message: "OK" }, result.hash)
    end

    def test_cancel_payment
      transaction_id = "1234-asdf-4567"
      expectations = { call_url: "https://payments.comgate.cz/v1.0/cancel",
                       call_payload: { transId: transaction_id,
                                       merchant: gateway_options[:merchant_gateway_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "0",
                                        "message" => "OK" },
                       test_call: false }

      result = expect_successful_api_call_with(expectations) do
        gateway.cancel_transaction(transaction_id: transaction_id)
      end

      assert !result.redirect?
      assert_equal({ code: 0, message: "OK" }, result.hash)
    end

    def test_get_payment_state
      transaction_id = "1234-4567-89AB"

      expectations = { call_url: "https://payments.comgate.cz/v1.0/status",
                       call_payload: { merchant: gateway_options[:merchant_gateway_id],
                                       transId: transaction_id,
                                       secret: gateway_options[:client_secret] },

                       response_body: { "code" => "0",
                                        "message" => "OK",
                                        "merchant" => gateway_options[:merchant_gateway_id].to_s,
                                        "test" => "false",
                                        "price" => "12900",
                                        "curr" => "CZK",
                                        "label" => "Automaticky obnovované předplatné pro ABC",
                                        "refId" => "62bdf52e1fdcdd5f02d",
                                        "method" => "CARD_CZ_CSOB_2",
                                        "email" => "payer1@gmail.com",
                                        "name" => "product name ABC",
                                        "transId" => "3IX8-NZ9I-KDTO",
                                        "secret" => "other_secret",
                                        "status" => "PAID",
                                        "fee" => "unknown",
                                        "vs" => "739689656",
                                        "payer_acc" => "account_num",
                                        "payerAcc" => "account_num_again",
                                        "payer_name" => "me",
                                        "payerName" => "me again!" },
                       test_call: false }

      result = expect_successful_api_call_with(expectations) do
        gateway.check_state(transaction_id: transaction_id)
      end

      expected_gateway_response_hash = {
        code: 0,
        message: "OK",
        merchant: { gateway_id: "some_id_from_comgate" },
        test: false,
        transaction_id: "3IX8-NZ9I-KDTO",
        state: :paid,
        payment: {
          amount_in_cents: 12_900,
          currency: "CZK",
          label: "Automaticky obnovované předplatné pro ABC",
          reference_id: "62bdf52e1fdcdd5f02d",
          method: "CARD_CZ_CSOB_2",
          product_name: "product name ABC",
          fee: nil,
          variable_symbol: 739_689_656
        },
        payer: {
          email: "payer1@gmail.com",
          account_number: "account_num_again",
          account_name: "me again!"
        }
      }
      assert !result.redirect?
      assert_nil result.redirect_to
      assert_equal expected_gateway_response_hash, result.hash
    end

    def test_get_available_payment_methods
      response_body = { "methods" => [
        {
          "id" => "CARD_CZ_CSOB_2",
          "name" => "Platební karta",
          "description" => "On-line platba platební kartou.",
          "logo" => "https://payments.comgate.cz/assets/images/logos/CARD_CZ_CSOB_2.png?v=1.4"
        },
        {
          "id" => "APPLEPAY_REDIRECT",
          "name" => "Apple Pay",
          "description" => "On-line platba pomocí Apple Pay.",
          "logo" => "https://payments.comgate.cz/assets/images/logos/APPLEPAY_REDIRECT.png?v=1.4"
        },
        {
          "id" => "GOOGLEPAY_REDIRECT",
          "name" => "Google Pay",
          "description" => "On-line platba pomocí Google Pay.",
          "logo" => "https://payments.comgate.cz/assets/images/logos/GOOGLEPAY_REDIRECT.png?v=1.4"
        },
        {
          "id" => "LATER_TWISTO",
          "name" => "Twisto",
          "description" => "Twisto - Platba do 30 dnů",
          "logo" => "https://payments.comgate.cz/assets/images/logos/LATER_TWISTO.png?v=1.4"
        },
        {
          "id" => "PART_TWISTO",
          "name" => "Twisto Nákup na třetiny",
          "description" => "Bez navýšení, ve třech měsíčních splátkách",
          "logo" => "https://payments.comgate.cz/assets/images/logos/PART_TWISTO.png?v=1.4"
        },
        {
          "id" => "BANK_CZ_RB",
          "name" => "Raiffeisenbank",
          "description" => "On-line platba pro majitele účtu u Raiffeisenbank.",
          "logo" => "https://payments.comgate.cz/assets/images/logos/BANK_CZ_RB.png?v=1.4"
        },
        {
          "id" => "BANK_CZ_OTHER",
          "name" => "Ostatní banky",
          "description" => "Bankovní převod pro majitele účtu u jiné banky (CZ).",
          "logo" => "https://payments.comgate.cz/assets/images/logos/BANK_CZ_OTHER.png?v=1.4"
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
                        secret: gateway_options[:client_secret] },
        response_body: response_body,
        test_call: false
      }

      result = expect_successful_api_call_with(full_params_expectations) do
        gateway.allowed_payment_methods(params)
      end

      result_array = response_body["methods"].collect(&:deep_symbolize_keys)
      assert_equal result_array, result.array
      assert_nil result.hash
    end

    def test_get_transfers_list
      time_as_date = Time.new(2023, 4, 14)
      expectations = { call_url: "https://payments.comgate.cz/v1.0/transferList",
                       call_payload: { merchant: gateway_options[:merchant_gateway_id],
                                       date: "2023-04-14",
                                       secret: gateway_options[:client_secret] },
                       response_body: [ # from json array
                         {
                           "transferId" => 33_459_010,
                           "transferDate" => "2023-04-14",
                           "accountCounterparty" => "5637796002/5500",
                           "accountOutgoing" => "242398277/0300",
                           "variableSymbol" => "675881954"
                         },
                         {
                           "transferId" => 33_459_009,
                           "transferDate" => "2023-04-14",
                           "accountCounterparty" => "5637796002/5500",
                           "accountOutgoing" => "242398277/0300",
                           "variableSymbol" => "675881281"
                         }
                       ],
                       test_call: false }

      result = expect_successful_api_call_with(expectations) do
        gateway.transfers_from(time_as_date)
      end

      expected_gateway_response_array = [ # from json array
        {
          transfer_id: 33_459_010,
          transfer_date: "2023-04-14",
          account_counterparty: "5637796002/5500",
          account_outgoing: "242398277/0300",
          variable_symbol: "675881954"
        },
        {
          transfer_id: 33_459_009,
          transfer_date: "2023-04-14",
          account_counterparty: "5637796002/5500",
          account_outgoing: "242398277/0300",
          variable_symbol: "675881281"
        }
      ]

      assert !result.redirect?
      assert_nil result.redirect_to
      assert_nil result.hash
      assert_equal expected_gateway_response_array, result.array
    end

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
                                       price: payment_params[:payment][:amount_in_cents],
                                       refId: payment_params[:payment][:reference_id],
                                       secret: gateway_options[:client_secret] },
                       response_body: { "code" => "1309",
                                        "message" => "Nespravná cena" },
                       errors: { api: ["[Error #1309] Nesprávná cena"] },
                       test_call: true }

      exception = expect_failed_api_call_with(expectations) do
        gateway.start_verification_transaction(payment_params)
      end

      assert_equal expectations[:errors].to_s, exception.message
      assert_equal RuntimeError, exception.class
    end

    private

    def gateway
      @gateway ||= Comgate::Gateway.new(gateway_options)
    end

    def gateway_options
      {
        merchant_gateway_id: "some_id_from_comgate",
        test_calls: true,
        client_secret: "Psst!ItIsPrivate!"
      }
    end

    def minimal_payment_params
      {
        payer: { email: "john@example.com" },
        payment: { currency: "CZK",
                   amount_in_cents: 100, # 1 CZK
                   label: "#2023-0123",
                   reference_id: "#2023-0123",
                   method: "ALL" }
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

    def expect_successful_api_call_with(expectations, &block)
      redirect_to = expectations[:response_body].is_a?(Hash) ? expectations[:response_body]["redirect"] : nil
      api_result = { http_code: 200,
                     redirect_to: redirect_to,
                     response_body: expectations[:response_body] }

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
      api_result = { http_code: 200,
                     response_body: expectations[:response_body] }

      assert_raises do
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
  end
end
