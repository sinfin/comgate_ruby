# frozen_string_literal: true

require "openssl"
require "net/http"

module Comgate
  class ApiCaller < BaseService
    KNOWN_CONNECTION_ERRORS = [
      Timeout::Error,
      Errno::EINVAL,
      Errno::ECONNRESET,
      EOFError,
      SocketError,
      Net::ReadTimeout,
      Net::HTTPBadResponse,
      Net::HTTPHeaderSyntaxError,
      Net::ProtocolError
    ].freeze

    attr_reader :payload, :url

    ResultHash = Struct.new(:code, :response_hash, keyword_init: true)

    def build_result
      call_api
      process_response
    end

    def initialize(url:, payload:, test_call: false)
      super()
      @url = url
      @payload = payload
      @payload.merge!(test: "true") if test_call
    end

    private

    attr_accessor :response

    def call_api
      self.response = https_conn.request(request)
    rescue *KNOWN_CONNECTION_ERRORS => e
      handle_connection_error(e)
    end

    def process_response
      return unless errors.empty?

      api_log(:debug, "Comgate API RESPONSE: #{response} with body:\n#{response.body}")

      @result = ResultHash.new(code: response.code.to_i, response_hash: parsed_response_body)
      return unless api_error?

      errors[:api] = [api_error_text]
    end

    def https_conn
      @https_conn ||= Net::HTTP.start(service_uri.host, service_uri.port, connection_options)
    end

    def request
      request = Net::HTTP::Post.new service_uri.request_uri, headers
      request.body = encoded_request_body

      debug_msg = "Commgate API REQUEST: #{request} to #{service_uri} " \
                  "with headers: #{headers}\n and body:\n#{request.body}"
      api_log(:debug, debug_msg)

      request
    end

    def service_uri
      @service_uri ||= URI.parse(url)
    end

    def headers
      {}
    end

    def connection_options
      {
        use_ssl: true,
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
        keep_alive_timeout: 30
        # ciphers: secure_and_available_ciphers,
        # cert: OpenSSL::X509::Certificate.new(File.read(configuration.certificate_path)),
        # cert_password: configuration.certificate_password,
        # key: OpenSSL::PKey::RSA.new(File.read(configuration.private_key_path), configuration.private_key_password),
        # cert_store: post_signum_ca_store
      }
    end

    def api_error?
      result.response_hash[:code].positive?
    end

    def api_error_text
      "[Error ##{result.response_hash[:code]}] #{result.response_hash[:message]}"
    end

    def handle_connection_error(error)
      @result = ResultHash.new(code: 500, response_hash: {})
      errors[:connection] = ["#{error.class} > #{service_uri} - #{error}"]
    end

    def encoded_request_body
      URI.encode_www_form(payload)
    end

    def parsed_response_body
      resp = symbolize_keys(URI.decode_www_form(response.body).to_h)
      resp[:code] = resp[:code].to_i if resp[:code]
      resp
    end

    def api_log(level, message)
      if defined?(Rails)
        Rails.logger.send(forced_log_level(level), message)
      else
        puts("#{Time.now} [#{forced_log_level(level)}] #{message}")
      end
    end

    def forced_log_level(original_level)
      levels = { debug: 0, info: 1, error: 2 }
      minimal_level = :error
      levels[original_level] > levels[minimal_level] ? original_level : minimal_level
    end

    def symbolize_keys(hash)
      res = {}
      hash.each_pair do |k, v|
        res[k.to_sym] = v
      end
      res
    end
  end
end