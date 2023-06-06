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
      price: %i[payment amount_in_cents],
      amount: %i[payment amount_in_cents],
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

      ## not used for Comgate, but for other Gateway payments they are needed
      ## so here they are for evidence
      # firstName: %i[payer first_name],
      # lastName: %i[payer last_name],
      # street: %i[payer street_line],
      # city: %i[payer city],
      # postalCode: %i[payer postal_code],
      # payerCountryCode: %i[payer country_code],
      # description: %i[payment description],
      # returnUrl: %i[options shop_return_url],
      # callbackUrl: %i[options callback_url],

      # responses
      transId: %i[transaction_id],
      transferId: %i[transfer_id],
      code: %i[code],
      message: %i[message],
      payerId: %i[payer id],
      payerName: %i[payer account_name],
      payer_name: %i[payer account_name],
      payerAcc: %i[payer account_number],
      payer_acc: %i[payer account_number],
      fee: %i[payment fee],
      methods: %i[methods],
      vs: %i[payment variable_symbol],
      variableSymbol: %i[variable_symbol],
      transferDate: %i[transfer_date],
      accountCounterparty: %i[account_counterparty],
      accountOutgoing: %i[account_outgoing],
      status: %i[state],
      test: %i[test],
      merchant: %i[merchant gateway_id],
      secret: %i[secret],
      redirect: %i[redirect_to]
    }.freeze

    attr_reader :options

    def initialize(options)
      @options = options
      return unless options[:merchant_gateway_id].nil? || options[:client_secret].nil? || options[:test_calls].nil?

      raise ArgumentError, "options have to include :merchant_gateway_id, :client_secret and :test_calls"
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

    def repeat_recurring_transaction(payment_data)
      init_transaction_id = payment_data[:payment][:recurrence].delete(:init_transaction_id)
      make_call(url: "#{BASE_URL}/recurring",
                payload: single_payment_payload(payment_data).merge(initRecurringId: init_transaction_id),
                test_call: test_call?(payment_data[:test]))
    end

    def start_verification_transaction(payment_data)
      make_call(url: "#{BASE_URL}/create",
                payload: single_payment_payload(payment_data).merge(verification: true),
                test_call: test_call?(payment_data[:test]))
    end

    def start_preauthorized_transaction(payment_data)
      make_call(url: "#{BASE_URL}/create",
                payload: single_payment_payload(payment_data).merge(preauth: true),
                test_call: test_call?(payment_data[:test]))
    end

    def confirm_preauthorized_transaction(payment_data)
      params = convert_data_to_comgate_params(%i[transId amount], payment_data, required: true)

      make_call(url: "#{BASE_URL}/capturePreauth",
                payload: gateway_params.merge(params),
                test_call: false)
    end

    def cancel_preauthorized_transaction(transaction_id:)
      make_call(url: "#{BASE_URL}/cancelPreauth",
                payload: gateway_params.merge(transId: transaction_id),
                test_call: false)
    end

    def refund_transaction(payment_data)
      refund_params = convert_data_to_comgate_params(%i[transId amount], payment_data, required: true)
      refund_params.merge!(convert_data_to_comgate_params(%i[curr refId], payment_data, required: false))

      make_call(url: "#{BASE_URL}/refund",
                payload: gateway_params.merge(refund_params),
                test_call: test_call?(payment_data[:test]))
    end

    def cancel_transaction(transaction_id:)
      make_call(url: "#{BASE_URL}/cancel",
                payload: gateway_params.merge(transId: transaction_id),
                test_call: false)
    end

    def check_transaction(transaction_id:)
      make_call(url: "#{BASE_URL}/status",
                payload: gateway_params.merge(transId: transaction_id),
                test_call: false)
    end
    alias check_state check_transaction # backward compatibility

    def process_callback(comgate_params)
      Comgate::Response.new({ response_body: comgate_params }, DATA_CONVERSION_HASH)
    end
    alias process_payment_callback process_callback  # backward compatibility

    def allowed_payment_methods(payment_data)
      ph = gateway_params.merge(convert_data_to_comgate_params(%i[curr lang country], payment_data, required: false))

      response = make_call(url: "#{BASE_URL}/methods",
                           payload: ph,
                           test_call: false,
                           conversion_hash: { name: [:name] })
      response.array = response.hash[:methods]
      response.hash = nil
      response
    end

    def transfers_from(date_or_time)
      date_str = date_or_time.strftime("%Y-%m-%d")

      make_call(url: "#{BASE_URL}/transferList",
                payload: gateway_params.merge({ date: date_str }),
                test_call: false)
    end

    private

    attr_reader :payment_data

    def make_call(url:, payload:, test_call:, conversion_hash: DATA_CONVERSION_HASH)
      raise "There are errors in pre-api-call phase: #{payload[:errors]}" unless payload[:errors].nil?

      srv = Comgate::ApiCaller.call(url: url, payload: payload, test_call: test_call)
      if srv.success?
        Comgate::Response.new(srv.result, conversion_hash)
      else
        handle_failure_from(srv.errors)
      end
    end

    def test_call?(test_from_data = nil)
      test_from_data.nil? ? test_calls_used? : (test_from_data == true)
    end

    def handle_failure_from(errors)
      raise errors.to_s
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
        secret: options[:client_secret] }
    end

    def convert_data_to_comgate_params(comgate_keys, data, required:)
      h = {}
      comgate_keys.each do |comg_key|
        dig_keys = DATA_CONVERSION_HASH[comg_key.to_sym]
        raise "comgate key '#{comg_key}' is not setup in conversion_hash" if dig_keys.nil?

        value = data.dig(*dig_keys)
        if value.nil?
          if required
            h[:errors] = [] if h[:errors].nil?
            h[:errors] << "Missing value for `params#{dig_keys.collect { |k| "[:#{k}]" }.join}` in `#{data}`"
          end
        else
          h[comg_key] = value
        end
      end
      h
    end
  end
end
