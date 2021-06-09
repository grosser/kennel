# frozen_string_literal: true
module Kennel
  # encapsulates knowledge around how the api works
  class Api
    CACHE_FILE = "tmp/cache/details"

    def initialize(app_key, api_key)
      @app_key = app_key
      @api_key = api_key
      @client = Faraday.new(url: "https://app.datadoghq.com") { |c| c.adapter :net_http_persistent }
    end

    def show(api_resource, id, params = {})
      reply = request :get, api_url(api_resource, id), params: params
      api_resource == "slo" || api_resource == 'logs/config/metrics' ? reply[:data] : reply
    end

    def list(api_resource, params = {})
      if api_resource == "slo"
        raise ArgumentError if params[:limit] || params[:offset]
        limit = 1000
        offset = 0
        all = []

        loop do
          result = request :get, api_url(api_resource), params: params.merge(limit: limit, offset: offset)
          data = result.fetch(:data)
          all.concat data
          break all if data.size < limit
          offset += limit
        end
      else
        result = request :get, api_url(api_resource), params: params
        result = result.fetch(:dashboards) if api_resource == "dashboard"
        result
      end
    end

    def create(api_resource, attributes)
      attributes = { data: attributes } if api_resource == 'logs/config/metrics'
      reply = request :post, api_url(api_resource), body: attributes
      if api_resource == "slo"
        reply[:data].first
      elsif api_resource == 'logs/config/metrics'
        reply[:data]
      else
        reply
      end
    end

    def update(api_resource, id, attributes)
      attributes = { data: attributes } if api_resource == 'logs/config/metrics'
      reply = request :put, api_url(api_resource, id), body: attributes
      api_resource == 'logs/config/metrics' ? reply[:data] : reply
    end

    # - force=true to not dead-lock on dependent monitors+slos
    #   external dependency on kennel managed resources is their problem, we don't block on it
    #   (?force=true did not work, force for dashboard is not documented but does not blow up)
    def delete(api_resource, id)
      request :delete, api_url(api_resource, id), params: { force: "true" }, ignore_404: true
    end

    def fill_details!(api_resource, list)
      return unless api_resource == "dashboard"
      details_cache do |cache|
        Utils.parallel(list) { |a| fill_detail!(api_resource, a, cache) }
      end
    end

    private

    def api_url(api_resource, id = nil)
      api_version = (api_resource == 'logs/config/metrics') ? 'v2' : 'v1'
      url = "/api/#{api_version}/#{api_resource}"
      url += "/#{id}" if id
      url
    end

    # Make diff work even though we cannot mass-fetch definitions
    def fill_detail!(api_resource, a, cache)
      args = [api_resource, a.fetch(:id)]
      full = cache.fetch(args, a.fetch(:modified_at)) { show(*args) }
      a.merge!(full)
    end

    def details_cache(&block)
      cache = FileCache.new CACHE_FILE, Kennel::VERSION
      cache.open(&block)
    end

    def request(method, path, body: nil, params: {}, ignore_404: false)
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

      if !response.success? && (response.status != 404 || !ignore_404)
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
