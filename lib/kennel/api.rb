# frozen_string_literal: true
module Kennel
  class Api
    def initialize(app_key, api_key)
      @app_key = app_key
      @api_key = api_key
      @client = Faraday.new(url: "https://app.datadoghq.com") { |c| c.adapter :net_http_persistent }
    end

    def show(api_resource, id, params = {})
      reply = request :get, "/api/v1/#{api_resource}/#{id}", params: params
      api_resource == "slo" ? reply[:data] : reply
    end

    def list(api_resource, params = {})
      request :get, "/api/v1/#{api_resource}", params: params
    end

    def create(api_resource, attributes)
      reply = request :post, "/api/v1/#{api_resource}", body: attributes
      api_resource == "slo" ? reply.first : reply
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
      tries = 2

      tries.times do |i|
        response = Utils.retry Faraday::ConnectionFailed, Faraday::TimeoutError, times: 2 do
          @client.send(method, "#{path}?#{query}") do |request|
            request.body = JSON.generate(body) if body
            request.headers["Content-type"] = "application/json"
          end
        end

        break if i == tries - 1 || method != :get || response.status < 500
        Kennel.err.puts "Retrying on server error #{response.status} for #{path}"
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
