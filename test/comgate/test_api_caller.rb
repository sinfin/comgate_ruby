# frozen_string_literal: true

require "test_helper"
require "net/http"

# rubocop:disable Layout/LineLength
module Comgate
  class TestApiCaller < Minitest::Test
    include MethodInvokingMatchersHelper

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
                                                headers: { "content-type" => "application/x-www-form-urlencoded; charset=UTF-8" })
      payload = { my_payload: "here" }
      url = "#{FAKE_URL}/create"

      matching_request = { method: "POST",
                           path: "/create",
                           body: URI.encode_www_form(payload.merge({ test: "true" })) }

      Net::HTTP.stub(:start, fake_http(api_response, matching_request)) do
        Comgate::ApiCaller.call(url: url, payload: payload, test_call: true)
      end
    end

    def test_can_handle_connection_errors # rubocop:disable Metrics/AbcSize
      url = "#{FAKE_URL}/create"

      Comgate::ApiCaller::KNOWN_CONNECTION_ERRORS.each do |error_class|
        service = call_with_connection_error(error_class, url)

        expect(service).to be_failure, "Service should fail for #{error_class}"
        expect(service.result[:http_code]).to eql(500), "result.http_code should be 500 for #{error_class}"
        expect(service.result[:response_body]).to be_nil, "result.response_hash should be nil for #{error_class}"
        expect(service.errors[:connection]).to include("#{error_class} > #{url} - #{error_class.new.message}")
        expect(service.result[:errors][:connection]).to include({ code: 500, message: "#{error_class} > #{url} - #{error_class.new.message}" })
      end
    end

    def test_can_handle_api_errors # rubocop:disable Metrics/AbcSize
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

      expected_response_hash = { "error" => "1400",
                                 "message" => err_message }

      expect(service).to be_failure, "Service should fail for non 0 code"
      expect(service.result[:http_code]).to eql(200), "result.http_code should be 200"
      expect(service.result[:response_body]).to eql(expected_response_hash),
                                                "result.response should be '#{expected_response_hash}'"
      expect(service.errors[:api]).to include("[Error #1400] #{expected_response_hash["message"]}")
      expect(service.result[:errors][:api]).to include({ code: 1400, message: expected_response_hash["message"] })
    end

    def test_can_handle_api_errors_without_error_attribute # rubocop:disable Metrics/AbcSize
      payload = { merchant: 123_456,
                  transId: "AB12-CD34-EF56",
                  secret: "x4q8OV3TJt6noJnfhjqJKyX3Z6Ych0y" }
      url = "#{FAKE_URL}/status"

      err_message = "Unauthorized access"
      service = call_returning_api_error({ code: 1400, message: err_message },
                                         { url: url, payload: payload })

      expected_response_hash = { "error" => "1400",
                                 "code" => "1400",
                                 "message" => err_message }

      expect(service).to be_failure, "Service should fail for non 0 code"
      expect(service.result[:http_code]).to eql(200), "result.http_code should be 200"
      expect(service.result[:response_body]).to eql(expected_response_hash),
                                                "result.response should be '#{expected_response_hash}'"
      expect(service.errors[:api]).to include("[Error #1400] #{expected_response_hash["message"]}")
      expect(service.result[:errors][:api]).to include({ code: 1400, message: expected_response_hash["message"] })
    end

    def test_redirect_if_response_is_302 # rubocop:disable Naming/VariableNumber
      redirect_path = "/redirect/here/please"

      payload = { my_payload: "here" , secret: "BIGSECRET"}
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

      assert_equal(nil, srv.result[:response_body])
      assert_equal expected_redirect_to_url, srv.result[:redirect_to]
    end

    def test_redirect_if_response_is_200_and_params_includes_redirect
      payload = { my_payload: "here" }
      url = "#{FAKE_URL}/create"
      expected_redirect_to_url = "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56"

      api_response = HttpResponseStubStruct.new(code: "200",
                                                body: "code=0&message=OK&transId=AB12-CD34-EF56&redirect=https%3A%2F%2Fpayments.comgate.cz%2Fclient%2Finstructions%2Findex%3Fid%3DAB12-CD34-EF56",
                                                uri: URI.parse(FAKE_URL),
                                                headers: { "content-type" => "application/x-www-form-urlencoded; charset=UTF-8" })

      matching_request = { method: "POST",
                           path: "/create",
                           body: URI.encode_www_form(payload.merge({ test: "true" })) }

      srv = Net::HTTP.stub(:start, fake_http(api_response, matching_request)) do
        Comgate::ApiCaller.call(url: url, payload: payload, test_call: true)
      end

      expected_response_hash = { "code" => "0",
                                 "message" => "OK",
                                 "transId" => "AB12-CD34-EF56",
                                 "redirect" => "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56" }
      assert_equal expected_response_hash, srv.result[:response_body]
      assert_equal expected_redirect_to_url, srv.result[:redirect_to]
    end

    def test_handle_url_encoded_response
      # DRY see: test_redirect_if_response_is_200_and_params_includes_redirect
    end

    def test_handle_json_response
      expected_result_hash = {
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
        },
        "secret" => "BIGSECRET"
      }

      api_response = HttpResponseStubStruct.new(code: "200",
                                                body: expected_result_hash.to_json,
                                                uri: URI.parse(FAKE_URL),
                                                headers: { "content-type" => "application/json; charset=UTF-8" })
      srv = Net::HTTP.stub(:start, fake_http(api_response)) do
        Comgate::ApiCaller.call(url: FAKE_URL, payload: {}, test_call: true)
      end

      assert_equal expected_result_hash, srv.result[:response_body]
    end

    def test_handle_json_array_response
      expected_result_array = [
        {
          "id" => "CARD_CZ_CSOB_2",
          "name" => "Platební karta"
        },
        {
          "id" => "APPLEPAY_REDIRECT",
          "name" => "Apple Pay"
        }
      ]

      api_response = HttpResponseStubStruct.new(code: "200",
                                                body: expected_result_array.to_json,
                                                uri: URI.parse(FAKE_URL),
                                                headers: { "content-type" => "application/json; charset=UTF-8" })

      srv = Net::HTTP.stub(:start, fake_http(api_response)) do
        Comgate::ApiCaller.call(url: FAKE_URL, payload: {}, test_call: true)
      end

      expect(srv.result[:response_body]).to eql(expected_result_array)
    end

    def test_handle_zip_file_response
      body_file_path = File.expand_path("./test/fixtures/csvs.zip")
      api_response = HttpResponseStubStruct.new(code: "200",
                                                body: File.read(body_file_path, encoding: "UTF-8"),
                                                uri: URI.parse(FAKE_URL),
                                                headers: { "content-type" => "application/zip; charset=UTF-8" })
      srv = Net::HTTP.stub(:start, fake_http(api_response)) do
        Comgate::ApiCaller.call(url: FAKE_URL, payload: {}, test_call: true)
      end

      tmp_file = srv.result[:response_body][:file]
      assert tmp_file.is_a?(Tempfile)
      assert File.exist?(tmp_file.path)

      # File.write("csvs_test.zip",tmp_file.read)
      # tmp_file.rewind
      # assert_equal File.read(body_file_path), tmp_file.read   # content is ok, but direct comparison not
      assert_equal File.open(body_file_path).size, tmp_file.size
      assert !tmp_file.size.zero? # rubocop:disable Style/ZeroLengthPredicate
    end

    def test_uses_proxy_if_set_in_initialize
      proxy_url = "proxy.me"
      proxy_port = 8080
      proxy_user = "user"
      proxy_pass = "pass"
      proxy_uri = "http://#{proxy_user}:#{proxy_pass}@#{proxy_url}:#{proxy_port}"

      payload = { my_payload: "here" }
      url = "#{FAKE_URL}/create"
      service_uri = URI.parse(url)

      matching_request = { method: "POST",
                           path: "/create",
                           body: URI.encode_www_form(payload.merge({ test: "true" })) }

      expected_connection_args = [service_uri.host,
                                  service_uri.port,
                                  proxy_url,
                                  proxy_port,
                                  proxy_user,
                                  proxy_pass,
                                  { use_ssl: true, verify_mode: 1, keep_alive_timeout: 30 }]
      conn_mock = fake_http(HttpResponseStubStruct.new(code: "200",
                                                       body: "code=0&message=OK+%28may+be?%29",
                                                       uri: URI.parse(FAKE_URL),
                                                       headers: { "content-type" => "application/x-www-form-urlencoded; charset=UTF-8" }),
                            matching_request)
      conn_mock.expect(:==, false, [:not_passed])

      expect_method_called_on(object: Net::HTTP,
                              method: :start,
                              args: expected_connection_args,
                              kwargs: {},
                              return_value: conn_mock) do
        Comgate::ApiCaller.call(url: url, payload: payload, test_call: true, proxy_uri: proxy_uri)
      end
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
                                                      headers: { "content-type" => "application/x-www-form-urlencoded; charset=UTF-8" })

      Net::HTTP.stub(:start, fake_http(api_error_response)) do
        Comgate::ApiCaller.call(url: request_hash[:url], payload: request_hash[:payload], test_call: true)
      end
    end
  end
end
# rubocop:enable Layout/LineLength
