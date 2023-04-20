# frozen_string_literal: true

require "openssl"
require "net/http"
require "json"

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

    def initialize(url:, payload:, test_call: false)
      super()
      @url = url
      @payload = payload
      @payload.merge!(test: "true") if test_call
    end

    def build_result
      call_api
      process_response
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

      @result = {
        http_code: response.code.to_i,
        redirect_to: find_redirect_to,
        response_body: decoded_response_body
      }

      record_api_error
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
      { "Content-Type" => "application/x-www-form-urlencoded" }
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

    def find_redirect_to
      case response&.code&.to_i
      when 302
        response_location
      when 200
        decoded_response_body.is_a?(Hash) ? decoded_response_body["redirect"] : nil
      end
    end

    def response_redirect?
      !redirect_to.nil?
    end

    def record_api_error
      return unless api_error?

      errors[:api] = ["[Error ##{result[:response_body]["error"]}] #{result[:response_body]["message"]}"]
      @result[:errors] = { api: { code: result[:response_body]["error"].to_i,
                                  message: result[:response_body]["message"] } }
    end

    def api_error?
      return false unless decoded_response_body.is_a?(Hash)

      decoded_response_body["error"].to_i.positive?
    end

    def handle_connection_error(error)
      errors[:connection] = ["#{error.class} > #{service_uri} - #{error}"]

      @result = {
        http_code: 500,
        errors: { connection: [{ code: 500, message: "#{error.class} > #{service_uri} - #{error}" }] }
      }
    end

    def encoded_request_body
      URI.encode_www_form(payload)
    end

    def decoded_response_body
      @decoded_response_body ||= case response_content_type
                                 when :url_encoded
                                   URI.decode_www_form(response.body).to_h
                                 when :json
                                   JSON.parse(response.body)
                                 end
    end

    def api_log(level, message)
      if defined?(Rails) && Rails.respond_to?(:logger)
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

    def response_location
      path_or_url = response["location"]
      return nil if path_or_url == ""

      response_uri = URI.parse(path_or_url)
      response_uri = URI.join(url, response_uri) if response_uri.relative?
      response_uri.to_s
    end

    def response_content_type
      rct = response["content-type"]
      return nil if rct.nil?

      if rct.include?("json")
        :json
      elsif rct.include?("form-urlencoded")
        :url_encoded
      else
        raise "Uncaptured content type: '#{rct}'"
      end
    end
  end
end
