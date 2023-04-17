# frozen_string_literal: true

require "base64"

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
      verification: %i[payment verification_payment],

      # responses
      transId: %i[transaction_id],
      code: %i[code],
      message: %i[message],
      payerId: %i[payer id],
      payerName: %i[payer account_name],
      payer_name: %i[payer account_name],
      payerAcc: %i[payer account_number],
      payer_acc: %i[payer account_number],
      fee: %i[payment fee],
      methods: %i[methods],
      redirect: %i[redirect],
      vs: %i[payment variable_symbol]
    }.freeze

    attr_reader :options, :result

    def initialize(options)
      @options = options
      if options[:merchant_gateway_id].nil? || options[:secret].nil? || options[:test_calls].nil?
        raise ArgumentError "options have to include :merchant_gateway_id, :secret and :test_calls"
      end

      @redirect_to = nil
    end

    def test_calls_used?
      options[:test_calls] == true
    end

    def start_transaction(payment_data)
      make_call(url: "#{BASE_URL}/create",
                payload: single_payment_payload(payment_data),
                test_call: test_call?(payment_data[:test]))
    end

    def start_recurring_transaction(payment_data)
      make_call(url: "#{BASE_URL}/create",
                payload: single_payment_payload(payment_data).merge(initRecurring: true),
                test_call: test_call?(payment_data[:test]))
    end

    def repeat_recurring_transaction(transaction_id:, payment_data:)
      make_call(url: "#{BASE_URL}/recurring",
                payload: single_payment_payload(payment_data).merge(initRecurringId: transaction_id),
                test_call: test_call?(payment_data[:test]))
    end

    def start_verfication_transaction(payment_data)
      make_call(url: "#{BASE_URL}/create",
                payload: single_payment_payload(payment_data).merge(verification: true),
                test_call: test_call?(payment_data[:test]))
    end

    def check_state(transaction_id:)
      make_call(url: "#{BASE_URL}/status",
                payload: gateway_params.merge(transId: transaction_id),
                test_call: false)
    end

    def allowed_payment_methods(params)
      ph = gateway_params.merge(convert_data_to_comgate_params(%i[curr lang country], params, required: false))

      make_call(url: "#{BASE_URL}/methods",
                payload: ph,
                test_call: false)
    end

    private

    attr_reader :payment_data

    def make_call(url:, payload:, test_call:)
      srv = Comgate::ApiCaller.call(url: url, payload: payload, test_call: test_call)
      if srv.success?
        @result = modify_api_call_result(srv.result)
      else
        handle_failure_from(srv)
      end
    end

    def test_call?(test_from_data = nil)
      test_from_data.nil? ? test_calls_used? : (test_from_data == true)
    end

    def single_payment_payload(payment_data)
      required_keys = %i[curr email label method price refId]
      optional_keys = %i[account applePayPayload country dynamicExpiration embedded expirationTime lang name phone
                         preauth verification]

      ph = gateway_params.merge({ prepareOnly: true })
      ph.merge!(convert_data_to_comgate_params(required_keys, payment_data, required: true))
      ph.merge!(convert_data_to_comgate_params(optional_keys, payment_data, required: false))
      ph[:applePayPayload] = Base64.encode64(ph[:applePayPayload]) unless ph[:applePayPayload].nil?
      ph
    end

    def gateway_params
      { merchant: options[:merchant_gateway_id],
        secret: options[:secret] }
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

    def convert_comgate_params_to_data(comgate_params)
      h = {}
      comgate_params.each_pair do |k, v|
        build_keys = DATA_CONVERSION_HASH[k.to_sym]&.dup
        if build_keys.nil?
          h[k] = v
        else
          last_key = build_keys.delete(build_keys.last)
          hash_at_level = h
          build_keys.each do |bk|
            hash_at_level[bk] = {} if hash_at_level[bk].nil?
            hash_at_level = hash_at_level[bk]
          end
          hash_at_level[last_key] = v
        end
      end
      h
    end

    def modify_api_call_result(result)
      result.response_hash.delete(:secret)
      result.response_hash = convert_comgate_params_to_data(result.response_hash)
      result
    end

    def handle_failure_from(result)
      raise result.errors.to_s
    end

    # _url = "#{BASE_URL}/create"
    # required_payment_data = {

    #   currency: "x", # currency code (ISO 4217). Available CZK, EUR, PLN, HUF, USD, GBP, RON, NOK, SEK. 
    #   email: "x", # buyer email
    #   label: "x", # 1-16 chars
    #   merchant: "x", # Comgate shop identifier (see  Client Portal -> e-shop settings -> e-shop connection)
    #   payment_method: "x", # "ALL" will offer methods to chose from
    #   prepare_only: false, # background payment?
    #   price_in_cents: 1, # cents, pennies, halere.
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
