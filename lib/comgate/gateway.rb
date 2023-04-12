# frozen_string_literal: true

module Comgate
  class Gateway
    BASE_URL = "https://payments.comgate.cz/v1.0"
    DATA_CONVERSION_HASH = {
      curr: %i[payment currency],
      email: %i[payer email],
      label: %i[payment label],
      method: %i[payment method],
      price: %i[payment price_in_cents],
      refId: %i[payment reference_id],
      account: %i[merchant target_shop_account],
      applePayPayload: %i[payment apple_pay_payload],
      country: %i[options country_code],
      dynamicExpiration: %i[payment dynamic_expiration],
      embedded: %i[options embedded_iframe],
      expirationTime: %i[payment expiration_time],
      lang: %i[options language_code],
      name: %i[payment product_name],
      phone: %i[payer phone],
      preauth: %i[payment preauthorization],
      verification: %i[payment verification_payment]
    }.freeze

    attr_reader :options, :result

    def initialize(options)
      @options = options
      @redirect_to = nil
    end

    def test_calls_used?
      options[:test_calls] == true
    end

    def create_payment(payment_data)
      srv = Comgate::ApiCaller.call(url: "#{BASE_URL}/create",
                                    payload: single_payment_payload_for(payment_data),
                                    test_call: test_call_for?(payment_data))
      if srv.success?
        @result = srv.result
      else
        pass_failure_from(srv)
      end
    end

    private

    def test_call_for?(payment_data)
      test_calls_used? || payment_data[:test]
    end

    def single_payment_payload_for(payment_data)
      required_keys = %i[curr email label method price refId]
      optional_keys = %i[account applePayPayload country dynamicExpiration embedded expirationTime lang name phone
                         preauth verification]

      ph = {
        merchant: options[:merchant_gateway_id],
        prepareOnly: (payment_data.dig(:payment, :at_background) || false),
        secret: nil
      }
      ph.merge!(convert_data_to_comgate_params(required_keys, payment_data, required: true))
      ph.merge!(convert_data_to_comgate_params(optional_keys, payment_data, required: false))
      ph
    end

    def convert_data_to_comgate_params(comgate_keys, data, required:)
      h = {}
      comgate_keys.each do |comg_key|
        dig_keys = DATA_CONVERSION_HASH[comg_key.to_sym]
        raise "comgate key '#{comg_key}' is not setup in conversion_hash" if dig_keys.nil?

        value = data.dig(*dig_keys)
        if value.nil?
          errors[:params] << "Missing value for param #{dig_keys.join(" =>")}" if required
        else
          h[comg_key] = value
        end
      end
      h
    end

    # _url = "#{BASE_URL}/create"
    # required_payment_data = {

    #   currency: "x", # currency code (ISO 4217). Available CZK, EUR, PLN, HUF, USD, GBP, RON, NOK, SEK. 
    #   email: "x", # buyer email
    #   label: "x", # 1-16 chars
    #   merchant: "x", # Comgate shop identifier (see  Client Portal -> e-shop settings -> e-shop connection)
    #   payment_method: "x", # "ALL" will offer methods to chose from
    #   prepare_only: false, # background payment?
    #   price_in_hundreths: 1, # cents, pennies, halere.
    #                            Must be in minimum of 1 CZK; 0,1 EUR; 1 PLN; 100 HUF;
    #                            1 USD; 1 GBP; 5 RON; 0,5 NOK; 0,5 SEK.
    #                            reccuring_payment_id: "x", # payment_id from initall reccuring payment
    #                            reference_id: "x", # eshop payment identifier (eg.: order number)

    # }
    # optional_payment_data ={
    #   target_shop_account: "x",
    #   apple_pay_payload: "x", # base64 encoded payment data
    #   country_code: "x", # iso_code_2 or "ALL"
    #   dynamic_expiration: "x",
    #   embedded_iframes: "x",
    #   expiration_time: "x", # in minutes OR hours OR days , in range of "30m" .... "10h" ..... "7d"
    #   init_reccuring_payments: false, # first of reccuring payments?
    #   lang_code: "x", # (ISO 639-1) %w[cs sk en es it pl fr ro de hu si hr no sv]
    #   product_name: "x",
    #   phone: "x", # buyer's phone
    #   preauthorization: false, # pre-authoriaziton payment?
    #   background_secret: "x",
    #   test: false, # testing payment?
    #   verification_payment: false, # verification payment?
    # }

    # Comgate::Response.new(api_call.result.response_hash)

    # https://payments.comgate.cz/v1.0/capturePreauth
    # https://payments.comgate.cz/v1.0/cancelPreauth
    # https://payments.comgate.cz/v1.0/recurring
    # https://payments.comgate.cz/v1.0/refund
    # https://payments.comgate.cz/v1.0/cancel
    # https://payments.comgate.cz/v1.0/status
    # https://payments.comgate.cz/v1.0/methods
    # https://payments.comgate.cz/v1.0/transferList
  end
end
