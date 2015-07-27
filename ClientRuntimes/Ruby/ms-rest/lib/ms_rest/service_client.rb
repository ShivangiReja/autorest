# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.

module MsRest
  #
  # Class which represents a point of access to the REST API.
  #
  class ServiceClient

    # @return [Hash] custom headers which are attached to the HTTP requests.
    attr_accessor :custom_headers

    # @return [MsRest::ServiceClientCredentials] the credentials object.
    attr_accessor :credentials

    # @return [Array] filters to be applied to the HTTP requests.
    attr_accessor :options

    # @return [String] value of cookies.
    attr_accessor :cookies

    #
    # Creates and initialize new instance of the ServiceClient class.
    #
    # @param credentials [MsRest::ServiceClientCredentials] credentials to authorize
    # HTTP requests made by the service client.
    # @param options [Array] filters to be applied to the HTTP requests.
    #
    def initialize(credentials, options)
      @credentials = credentials
      @options = options
      @custom_headers = {}
    end

    #
    # Verifies whether given response is about authentication token expiration.
    # @param response [Net::HTTPResponse] http response to verify.
    #
    # @return [Bool] true if response is about authentication token expiration, false otherwise.
    def is_token_expired_response(response)
      return false unless response.is_a?(Net::HTTPUnauthorized)

      begin
        response_body = JSON.load(response.body)
        error_code = response_body['error']['code']
        error_message = response_body['error']['message']
      rescue Exception => e
        return false
      end

      return (error_code == 'AuthenticationFailed' && (error_message.start_with?('The access token expiry') || (error_message.start_with?('The access token is missing or invalid'))))
    end

    #
    # Makes the HTTP request by the given uri.
    # @param request [Net::HTTPRequest] the HTTP request to perform.
    # @param uri [URI::HTTP] the URI for HTTP request.
    #
    # @return [Net::HTTPResponse] the HTTP response.
    def make_http_request(request, uri)
      http = Net::HTTP.new(uri.host, uri.port)

      if uri.scheme == 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      # adding custom HTTP headers
      @custom_headers.each do |key, value|
        request.add_field(key, value)
      end

      # sign in
      @credentials.sign_request(request) unless @credentials.nil?

      # TODO: add proper retry policy.

      retry_count = 5
      response = nil

      retry_count.times do
        response = http.request(request)

        if (is_token_expired_response(response) && @credentials.respond_to?(:acquire_token))
          @credentials.acquire_token()
          @credentials.sign_request(request)
          redo
        end

        unless response['set-cookie'].nil?
          cookies = response['set-cookie']
        end

        unless cookies.nil?
          request['cookie'] = cookies
        end

        if not (response.code.to_i == 408 ||
               (response.code.to_i >= 500 && response.code.to_i != 501 && response.code.to_i != 505))
          return response
        end
      end

      return response
    end
  end

end
