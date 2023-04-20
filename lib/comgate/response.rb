# frozen_string_literal: true

module Comgate
  class Response
    RESPONSE_CODES = {
      0 => "OK",
      1100 => "unknown error",
      1102 => "the specified language is not supported",
      1103 => "method incorrectly specified",
      1104 => "unable to load payment",
      1107 => "payment price is not supported",
      1200 => "database error",
      1301 => "unknown e-shop",
      1303 => "the link or language is missing",
      1304 => "invalid category",
      1305 => "product description is missing",
      1306 => "select the correct method",
      1308 => "the selected payment method is not allowed",
      1309 => "incorrect amount",
      1310 => "unknown currency",
      1311 => "invalid e-shop bank account identifier",
      1316 => "e-shop does not allow recurring payments",
      1317 => "invalid method - does not support recurring payments",
      1318 => "initial payment not found",
      1319 => "can not create a payment, a problem on the part of the bank",
      1399 => "unexpected result from database",
      1400 => "wrong query",
      1401 => "the refunded payment is in the CANCELED state",
      # or 1401 =>"Transaction FVN0-NS40-NA5B has not been authorized, current status: READY"
      1402 => "refund amount higher than allowed",
      1500 => "unexpected error"
    }.freeze

    attr_accessor :http_code, :redirect_to, :hash, :array, :errors
    attr_reader :params_conversion_hash

    def initialize(caller_result, params_conversion_hash = {})
      @params_conversion_hash = params_conversion_hash

      @http_code = caller_result[:http_code].to_i
      @errors = fill_error_messages(caller_result[:errors])
      @redirect_to = caller_result[:redirect_to]

      converted_body = convert_comgate_params_to_data(caller_result[:response_body])

      case converted_body
      when Hash
        @hash = converted_body
        @array = nil
      when Array
        @array = converted_body
        @hash = nil
      end
    end

    def redirect?
      !redirect_to.nil?
    end

    def error?
      !errors.nil?
    end

    private

    def convert_comgate_params_to_data(comgate_params)
      h = transform_comgate_params(comgate_params)
      return h unless h.is_a?(Hash)

      cleanup_hash(h)
    end

    def cleanup_hash(rsp_hash) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      rsp_hash.delete(:secret)

      rsp_hash[:state] = rsp_hash[:state].to_s.downcase.to_sym unless rsp_hash[:state].nil?
      unless rsp_hash.dig(:payment, :variable_symbol).nil?
        rsp_hash[:payment][:variable_symbol] = rsp_hash.dig(:payment, :variable_symbol).to_i
      end
      unless rsp_hash.dig(:payment, :amount_in_cents).nil?
        rsp_hash[:payment][:amount_in_cents] = rsp_hash.dig(:payment, :amount_in_cents).to_i
      end
      rsp_hash[:variable_symbol] = rsp_hash[:variable_symbol].to_i unless rsp_hash[:variable_symbol].nil?
      if (fee = rsp_hash.dig(:payment, :fee))
        rsp_hash[:payment][:fee] = fee == "unknown" ? nil : fee.to_f
      end

      rsp_hash[:code] = rsp_hash[:code].to_i if rsp_hash[:code]
      rsp_hash[:error] = rsp_hash[:error].to_i if rsp_hash[:error]

      rsp_hash[:message] = RESPONSE_CODES[rsp_hash[:code]] if rsp_hash[:message].to_s == "" && rsp_hash[:code]
      rsp_hash
    end

    def transform_comgate_params(comgate_params)
      case comgate_params
      when Hash
        transform_comgate_hash(comgate_params)
      when Array
        comgate_params.collect { |item| transform_comgate_params(item) }
      when "true"
        true
      when "false"
        false
      else
        comgate_params
      end
    end

    def transform_comgate_hash(comgate_params)
      h = {}
      comgate_params.each_pair do |k, v|
        build_keys = params_conversion_hash[k.to_sym]&.dup
        transformed_value = transform_comgate_params(v)

        if build_keys.nil? # not covered in params_conversion_hash
          h[k.to_sym] = transformed_value
        else
          last_key = build_keys.delete(build_keys.last)
          hash_at_level = h
          build_keys.each do |bk|
            hash_at_level[bk] = {} if hash_at_level[bk].nil?
            hash_at_level = hash_at_level[bk]
          end
          hash_at_level[last_key] = transformed_value
        end
      end
      h
    end

    def fill_error_messages(caller_errors)
      return nil if caller_errors.nil?
      return caller_errors if caller_errors[:api].nil?

      caller_errors[:api] = caller_errors[:api].collect do |err_h|
        err_h[:message] = RESPONSE_CODES[err_h[:code]] if err_h[:message].to_s == ""
        err_h
      end
      caller_errors
    end
  end
end
