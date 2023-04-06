# frozen_string_literal: true

require "test_helper"

module Comgate
  class TestApiCaller < Minitest::Test
    FAKE_URL = "http://test.me"
    HttpResponseStubStruct = Struct.new(:code, :body, :uri)

    def test_gateway_respects_test_setting
      api_response = HttpResponseStubStruct.new("200",
                                                "code=0&message=OK+%28may+be?%29",
                                                URI.parse(FAKE_URL))
      payload = {my_payload: "here"}
      url = FAKE_URL + "/create"
      fake_http = Minitest::Mock.new
      fake_http.expect(:request, api_response) do |argument|
        argument.is_a?(Net::HTTP::Post) &&
        argument.method == "POST" &&
        argument.path == "/create" &&
        argument.body == URI.encode_www_form(payload.merge({test: "true"}))
      end

      Net::HTTP.stub(:start, fake_http) do
        Comgate::ApiCaller.call(url: , payload: , test_call: true)
      end
    end


    def test_can_handle_connection_errors
      Comgate::ApiCaller::KNOWN_CONNECTION_ERRORS.each do |error_class|
        payload = {my_payload: "here"}
        url = FAKE_URL + "/create"

        expected_err_message = "#{error_class} > #{url} - #{error_class.new.message}"
        raises_exception = -> (*args) { raise error_class }

        service = nil
        Net::HTTP.stub(:start, raises_exception) do
          service = Comgate::ApiCaller.call(url: , payload: , test_call: true)
        end

        expect(service).to be_failure, "Service should fail for #{error_class}"
        expect(service.result.code).to eql(500), "result.code should be 500 for #{error_class}"
        expect(service.result.response_hash).to eql({}), "result.response should be '' for #{error_class}"
        expect(service.errors[:connection]).to include(expected_err_message)
      end
    end

    # def test_can_handle_api_errors
    #   response_body = '{
    #                       "message": "Wrong api key"
    #                    }'
    #   api_error_response = HttpResponseStubStruct.new("401",
    #                                                   response_body,
    #                                                   URI.parse("https://api2.ecomailapp.cz/lists"))

    #   fake_http = Minitest::Mock.new
    #   fake_http.expect(:request, api_error_response, [Net::HTTPRequest])

    #   service = Net::HTTP.stub(:start, fake_http) do
    #     Bi::Ecomail::ApiCaller.call(path: "/lists", http_method: "GET")
    #   end

    #   expected_response_body = JSON.parse(response_body).deep_symbolize_keys
    #   expect(service).to be_failure, "Service should fail for 401"
    #   expect(service.result.code).to eql(401), "result.code should be 401"
    #   expect(service.result.response).to eql(expected_response_body), "result.response should be '#{expected_response_body}'"
    #   expect(service.errors).to include({ api: response_body })
    # end
  end
end
