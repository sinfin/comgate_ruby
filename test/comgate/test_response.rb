# frozen_string_literal: true

require "test_helper"

module Comgate
  class TestResponse < Minitest::Test
    def test_convert_params_in_hash_response
      api_response_body = {
        "code" => "0",
        "message" => "OK",
        "transId" => "1234-4567-abcd"
      }

      caller_result = { response_body: api_response_body }

      cresp = Comgate::Response.new(caller_result, Comgate::Gateway::DATA_CONVERSION_HASH)

      expect(cresp.hash).to eql({ code: 0, message: "OK", transaction_id: "1234-4567-abcd" })
      expect(cresp.array).to eql(nil)
      expect(cresp.error?).to be false
    end

    def test_convert_maximal_params_in_hash_response # rubocop:disable Metrics/AbcSize
      # hash bellow is nonsense, response will never get that keys together
      api_response_body = {
        "code" => 0,
        "message" => "OK",
        "merchant" => "123456789",
        "test" => "true",
        "price" => "12900",
        "curr" => "CZK",
        "label" => "Automaticky obnovované předplatné pro ABC",
        "refId" => "62bdf52e1fdcdd5f02d",
        "method" => "CARD_CZ_CSOB_2",
        "email" => "payer1@gmail.com",
        "name" => "product name ABC",
        "transId" => "AB12-CD34-EF56",
        "secret" => "other_secret",
        "status" => "PAID",
        "fee" => "unknown",
        "vs" => "111222333",
        "payer_acc" => "account_num",
        "payerAcc" => "account_num_again",
        "payer_name" => "me",
        "payerName" => "me again!",

        "amount" => "333",
        "account" => "acc",
        "applePayPayload" => "payload",
        "country" => "country",
        "dynamicExpiration" => "true",
        "embedded" => "false",
        "expirationTime" => "66m",
        "lang" => "sk",
        "phone" => "+40123456789",
        "preauth" => "false",
        "verification" => "false",
        "transferId" => "98745632",
        "payerId" => "????",
        "methods" => "array of methods",
        "redirect" => "redirect_url",
        "variableSymbol" => "444555666",
        "transferDate" => "2023-04-05",
        "accountCounterparty" => "465654/231",
        "accountOutgoing" => "123156464/52631"
      }

      expected_result_hash = {
        account_counterparty: api_response_body["accountCounterparty"],
        account_outgoing: api_response_body["accountOutgoing"],
        transfer_date: api_response_body["transferDate"],
        transfer_id: api_response_body["transferId"],
        variable_symbol: api_response_body["variableSymbol"].to_i,

        code: api_response_body["code"].to_i,
        message: api_response_body["message"],
        state: api_response_body["status"].downcase.to_sym,
        redirect_to: api_response_body["redirect"],
        test: api_response_body["test"] == "true",
        transaction_id: api_response_body["transId"],

        merchant: {
          gateway_id: api_response_body["merchant"],
          target_shop_account: api_response_body["account"]
        },
        payer: {
          email: api_response_body["email"],
          phone: api_response_body["phone"],
          account_name: api_response_body["payerName"], # payerName" and "payer_name" goes to "account_name"
          account_number: api_response_body["payerAcc"], # payerAcc" and "payer_acc" goes to "account_number"
          id: api_response_body["payerId"]
        },
        payment: {
          # both "price" and "amount" is converted to "amount_in_cents"
          amount_in_cents: api_response_body["amount"].to_i,
          currency: api_response_body["curr"],
          label: api_response_body["label"],
          method: api_response_body["method"],
          reference_id: api_response_body["refId"],
          apple_pay_payload: api_response_body["applePayPayload"],
          dynamic_expiration: api_response_body["dynamicExpiration"] == "true",
          expiration_time: api_response_body["expirationTime"],
          product_name: api_response_body["name"],
          preauthorization: api_response_body["preauth"] == "true",
          verification_payment: api_response_body["verification"] == "true",
          fee: api_response_body["fee"] == "unknown" ? nil : api_response_body["fee"].to_f,
          variable_symbol: api_response_body["vs"].to_i
        },

        options: {
          country_code: api_response_body["country"],
          language_code: api_response_body["lang"],
          embedded_iframe: api_response_body["embedded"] == "true"
        },
        methods: api_response_body["methods"]
      }

      cresp = Comgate::Response.new({ response_body: api_response_body }, Comgate::Gateway::DATA_CONVERSION_HASH)

      expect(cresp.hash).to eql(expected_result_hash)
      expect(cresp.hash.keys).not_to include(:secret)
      expect(cresp.array).to eql(nil)
    end

    def test_convert_params_in_hash_containing_arrays_response
      caller_result = {
        response_body: {
          "methods" => [
            {
              "id" => "CARD_CZ_CSOB_2",
              "name" => "Platební karta"
            },
            {
              "id" => "APPLEPAY_REDIRECT",
              "name" => "Apple Pay"
            }
          ],
          "nested" => {
            "stuff" => "here",
            "and_also" => "there"
          }
        }
      }
      conversion_hash = { name: %i[product_name] }

      cresp = Comgate::Response.new(caller_result, conversion_hash)

      expected_result_hash = {
        methods: [
          { id: "CARD_CZ_CSOB_2", product_name: "Platební karta" },
          { id: "APPLEPAY_REDIRECT", product_name: "Apple Pay" }
        ],
        nested: { stuff: "here", and_also: "there" }
      }
      expect(cresp.hash).to eql(expected_result_hash)
      expect(cresp.array).to eql(nil)
    end

    def test_convert_params_in_array_response
      caller_result = {
        response_body: [
          {
            "id" => "CARD_CZ_CSOB_2",
            "name" => "Platební karta",
            "validTo" => "now"
          },
          {
            "id" => "APPLEPAY_REDIRECT",
            "name" => "Apple Pay",
            "validTo" => "now"
          }
        ]
      }

      conversion_hash = { id: %i[nested id],
                          name: %i[nested pname] }

      cresp = Comgate::Response.new(caller_result, conversion_hash)

      expected_array = [
        {
          nested: {
            id: "CARD_CZ_CSOB_2",
            pname: "Platební karta"
          },
          validTo: "now"
        },
        {
          nested: {
            id: "APPLEPAY_REDIRECT",
            pname: "Apple Pay"
          },
          validTo: "now"
        }
      ]
      expect(cresp.hash).to eql(nil)
      expect(cresp.array).to eql(expected_array)
    end

    def test_handles_redirection
      url = "http://example.com"
      caller_result = { http_code: 200,
                        redirect_to: url,
                        response_body: {} }

      cresp = Comgate::Response.new(caller_result, Comgate::Gateway::DATA_CONVERSION_HASH)

      expect(cresp.redirect_to).to eql(url)
      expect(cresp.redirect?).to be true
    end

    def test_handle_errors
      caller_result = {
        errors: { api: [{ code: 1400, message: "wrong query" }] },
        response_body: { "error" => "1400",
                         "message" => "not same wrong query" }
      }

      cresp = Comgate::Response.new(caller_result, Comgate::Gateway::DATA_CONVERSION_HASH)

      expect(cresp.hash).to eql({ error: 1400, message: "not same wrong query" })
      expect(cresp.array).to eql(nil)
      expect(cresp.error?).to be true
      expect(cresp.errors).to eql({ api: [{ code: 1400, message: "wrong query" }] })
    end

    def test_fill_in_missing_api_error_message
      caller_result = {
        errors: { api: [{ code: 1500, message: "" }] }
      }

      cresp = Comgate::Response.new(caller_result, Comgate::Gateway::DATA_CONVERSION_HASH)

      expect(cresp.error?).to be true
      expect(cresp.errors).to eql({ api: [{ code: 1500, message: "unexpected error" }] })
    end
  end
end
