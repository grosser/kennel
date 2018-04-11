# frozen_string_literal: true
module Kennel
  class Api
    def initialize(app_key, api_key)
      @app_key = app_key
      @api_key = api_key
      @client = Faraday.new(url: "https://app.datadoghq.com")
    end

    def show(api_resource, id)
      request :get, "/api/v1/#{api_resource}/#{id}"
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
      response = @client.send(method, "#{path}?#{query}") do |request|
        request.body = JSON.generate(body) if body
        request.headers["Content-type"] = "application/json"
      end
      raise "Error #{method} #{path} -> #{response.status}:\n#{response.body}" unless response.success?
      if response.body.empty?
        {}
      else
        JSON.parse(response.body, symbolize_names: true)
      end
    end
  end
end
