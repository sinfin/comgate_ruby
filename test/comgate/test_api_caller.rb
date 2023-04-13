# frozen_string_literal: true

require "test_helper"
require "net/http"

module Comgate
  class TestApiCaller < Minitest::Test
    FAKE_URL = "http://test.me"
    HttpResponseStubStruct = Struct.new(:code, :body, :uri, :headers, keyword_init: true) do
      def [](key)
        headers[key]
      end
    end

    def test_gateway_respects_test_setting
      api_response = HttpResponseStubStruct.new(code: "200",
                                                body: "code=0&message=OK+%28may+be?%29",
                                                uri: URI.parse(FAKE_URL),
                                                headers: {})
      payload = { my_payload: "here" }
      url = "#{FAKE_URL}/create"

      matching_request = { method: "POST",
                           path: "/create",
                           body: URI.encode_www_form(payload.merge({ test: "true" })) }

      Net::HTTP.stub(:start, fake_http(api_response, matching_request)) do
        Comgate::ApiCaller.call(url: url, payload: payload, test_call: true)
      end
    end

    def test_can_handle_connection_errors
      url = "#{FAKE_URL}/create"

      Comgate::ApiCaller::KNOWN_CONNECTION_ERRORS.each do |error_class|
        service = call_with_connection_error(error_class, url)

        expect(service).to be_failure, "Service should fail for #{error_class}"
        expect(service.result.code).to eql(500), "result.code should be 500 for #{error_class}"
        expect(service.result.response_hash).to eql({}), "result.response should be '' for #{error_class}"
        expect(service.errors[:connection]).to include("#{error_class} > #{url} - #{error_class.new.message}")
      end
    end

    def test_can_handle_api_errors
      # from API docs
      payload = { merchant: 123_456,
                  transId: "AB12-CD34-EF56",
                  secret: "x4q8OV3TJt6noJnfhjqJKyX3Z6Ych0y" }
      url = "#{FAKE_URL}/status"
      err_message = <<~ERR
        Payment not found (status), params: array (
          'merchant' => '123456',
          'secret' => 'x4q8OV3TJt6noJnfhjqJKyX3Z6Ych0y',
          'transId' => 'AB12-CD34-EF56',
        )
      ERR

      service = call_returning_api_error({ error: 1400, message: err_message },
                                         { url: url, payload: payload })

      expected_response_hash = { code: 1400,
                                 error: 1400,
                                 headers: {},
                                 message: err_message }

      expect(service).to be_failure, "Service should fail for non 0 code"
      expect(service.result.code).to eql(200), "result.code should be 200"
      expect(service.result.response_hash).to eql(expected_response_hash),
                                              "result.response should be '#{expected_response_hash}'"
      expect(service.errors[:api]).to include("[Error #1400] #{expected_response_hash[:message]}")
    end

    def test_redirect_if_response_is_302 # rubocop:disable Naming/VariableNumber
      redirect_path = "/redirect/here/please"

      payload = { my_payload: "here" }
      url = "#{FAKE_URL}/create"
      expected_redirect_to_url = "#{FAKE_URL}#{redirect_path}"

      api_response = HttpResponseStubStruct.new(code: 302,
                                                body: "Found",
                                                uri: "",
                                                headers: { "location" => redirect_path })

      matching_request = { method: "POST",
                           path: "/create",
                           body: URI.encode_www_form(payload.merge({ test: "true" })) }

      srv = Net::HTTP.stub(:start, fake_http(api_response, matching_request)) do
        Comgate::ApiCaller.call(url: url, payload: payload, test_call: true)
      end

      assert srv.result.redirect?
      assert_equal({ Found: "", headers: {} }, srv.result.response_hash)
      assert_equal expected_redirect_to_url, srv.result.redirect_to
    end

    def test_redirect_if_response_is_200_and_params_inludes_redirect
      payload = { my_payload: "here" }
      url = "#{FAKE_URL}/create"
      expected_redirect_to_url = "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56"

      api_response = HttpResponseStubStruct.new(code: "200",
                                                body: "code=0&message=OK&transId=AB12-CD34-EF56&redirect=https%3A%2F%2Fpayments.comgate.cz%2Fclient%2Finstructions%2Findex%3Fid%3DAB12-CD34-EF56", # rubocop:disable Layout/LineLength
                                                uri: URI.parse(FAKE_URL),
                                                headers: {})

      matching_request = { method: "POST",
                           path: "/create",
                           body: URI.encode_www_form(payload.merge({ test: "true" })) }

      srv = Net::HTTP.stub(:start, fake_http(api_response, matching_request)) do
        Comgate::ApiCaller.call(url: url, payload: payload, test_call: true)
      end

      expected_response_hash = { code: 0,
                                 message: "OK",
                                 transId: "AB12-CD34-EF56",
                                 redirect: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56",
                                 headers: {} }
      assert srv.result.redirect?
      assert_equal expected_response_hash, srv.result.response_hash
      assert_equal expected_redirect_to_url, srv.result.redirect_to
    end

    private

    def fake_http(api_response, matching_request = :any)
      fake_http = Minitest::Mock.new
      if matching_request == :any
        fake_http.expect(:request, api_response, [Net::HTTPRequest])
      else
        fake_http.expect(:request, api_response) do |argument|
          matching_request.all? do |k, v|
            if argument.send(k) == v
              true
            else
              puts("Non matching #{k}: expected '#{v}', actual '#{argument.send(k)}'.")
              false
            end
          end
        end
      end
      fake_http
    end

    def call_with_connection_error(error_class, url)
      payload = { my_payload: "here" }
      raises_exception = ->(*_args) { raise error_class }

      Net::HTTP.stub(:start, raises_exception) do
        Comgate::ApiCaller.call(url: url, payload: payload, test_call: true)
      end
    end

    def call_returning_api_error(response_hash, request_hash)
      response_body = URI.encode_www_form(response_hash)
      api_error_response = HttpResponseStubStruct.new(code: "200",
                                                      body: response_body,
                                                      uri: URI.parse("https://comgate.cz"),
                                                      headers: {})

      Net::HTTP.stub(:start, fake_http(api_error_response)) do
        Comgate::ApiCaller.call(url: request_hash[:url], payload: request_hash[:payload], test_call: true)
      end
    end
  end
end
