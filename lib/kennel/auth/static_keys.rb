# frozen_string_literal: true

module Kennel
  module Auth
    class StaticKeys
      def self.configured?
        ENV["DATADOG_APP_KEY"] && ENV["DATADOG_API_KEY"]
      end

      def initialize(app_key: ENV.fetch("DATADOG_APP_KEY"), api_key: ENV.fetch("DATADOG_API_KEY"))
        @app_key = app_key
        @api_key = api_key
      end

      attr_reader :app_key, :api_key

      def apply!(request)
        request.headers["DD-API-KEY"] = api_key
        request.headers["DD-APPLICATION-KEY"] = app_key
      end

      def prepare!
        true
      end

      def invalidate!
        false
      end

      def refresh!
        false
      end
    end
  end
end
