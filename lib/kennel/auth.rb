# frozen_string_literal: true

module Kennel
  module Auth
    class << self
      def build
        case auth_method
        when nil
          return StaticKeys.new if StaticKeys.configured?

          Kennel.err.puts "Warning: DATADOG_APP_KEY/DATADOG_API_KEY are not set, falling back to OAuth. Explicitly set DATADOG_AUTH_METHOD=oauth to silence this warning."
          OAuth.new
        when "static"
          raise "DATADOG_AUTH_METHOD=static requires DATADOG_APP_KEY and DATADOG_API_KEY" unless StaticKeys.configured?

          StaticKeys.new
        when "oauth"
          OAuth.new
        else
          raise "Unknown DATADOG_AUTH_METHOD=#{ENV["DATADOG_AUTH_METHOD"].inspect}, expected static or oauth"
        end
      end

      private

      def auth_method
        ENV["DATADOG_AUTH_METHOD"]&.downcase || (ENV["CI"] && "static")
      end
    end
  end
end
