# frozen_string_literal: true
module Kennel
  class Api
    def initialize(app_key, api_key)
      @app_key = app_key
      @api_key = api_key
      @client = Faraday.new(url: "https://app.datadoghq.com")
    end

    def show(api_resource, id, params = {})
      request :get, "/api/v1/#{api_resource}/#{id}", params: params
    end

    def list(api_resource, params)
      request :get, "/api/v1/#{api_resource}", params: params
    end

    def create(api_resource, attributes)
      request :post, "/api/v1/#{api_resource}", body: attributes
    end

    def update(api_resource, id, attributes)
      request :put, "/api/v1/#{api_resource}/#{id}", body: attributes
    end

    def delete(api_resource, id)
      request :delete, "/api/v1/#{api_resource}/#{id}"
    end

    private

    def request(method, path, body: nil, params: {})
      params = params.merge(application_key: @app_key, api_key: @api_key)
      query = Faraday::FlatParamsEncoder.encode(params)
      response = nil

      2.times do |i|
        response = @client.send(method, "#{path}?#{query}") do |request|
          request.body = JSON.generate(body) if body
          request.headers["Content-type"] = "application/json"
        end
        break if i == 1 || method != :get || response.status < 500
      end

      unless response.success?
        message = +"Error #{response.status} during #{method.upcase} #{path}\n"
        message << "request:\n#{JSON.pretty_generate(body)}\nresponse:\n" if body
        message << response.body
        raise message
      end

      if response.body.empty?
        {}
      else
        JSON.parse(response.body, symbolize_names: true)
      end
    end
  end
end
