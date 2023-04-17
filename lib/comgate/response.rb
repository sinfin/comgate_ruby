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
      1402 => "refund amount higher than allowed",
      1500 => "unexpected error"
    }.freeze

    def initialize(response_hash)
      @response_hash = response_hash || {}

      @response_hash[:code] = @response_hash[:code].to_i if @response_hash[:code]

      if @response_hash[:error]
        @response_hash[:error] = @response_hash[:error].to_i
        @response_hash[:code] = @response_hash[:error]
      end

      return unless @response_hash[:message].to_s == "" && @response_hash[:code]

      @response_hash[:message] = RESPONSE_CODES[response_hash[:code]]
    end

    def to_h
      @response_hash
    end
  end
end
