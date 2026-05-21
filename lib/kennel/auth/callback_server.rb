# frozen_string_literal: true

require "cgi"
require "timeout"

module Kennel
  module Auth
    class CallbackServer
      UnavailableError = Class.new(StandardError)

      REDIRECT_PORTS = [8000, 8080, 8888, 9000].freeze

      def initialize(pinned_port: nil, library_loader: -> { require "webrick" }, server_module: nil)
        @server_module = server_module || load_server_module(library_loader)
        @server = bind_server(pinned_port)
        @port = @server.config[:Port]
        @callback = nil
        mount_callback_handler
      end

      attr_reader :port

      def self.redirect_uris
        REDIRECT_PORTS.map { |port| "http://127.0.0.1:#{port}/oauth/callback" }
      end

      def redirect_uri
        "http://127.0.0.1:#{port}/oauth/callback"
      end

      def wait_for_callback(timeout: 300)
        Timeout.timeout(timeout) { @server.start }
        @callback || raise("OAuth callback finished without a result")
      rescue Timeout::Error
        @server.shutdown
        raise "OAuth callback timed out after #{timeout} seconds"
      end

      def close
        return unless @server

        @server.shutdown
      end

      private

      def bind_server(pinned_port)
        if pinned_port
          raise ArgumentError, "Unsupported callback port #{pinned_port}" unless REDIRECT_PORTS.include?(pinned_port)

          return build_server(pinned_port)
        end

        REDIRECT_PORTS.each do |candidate|
          return build_server(candidate)
        rescue Errno::EADDRINUSE
          next
        end

        raise "could not bind to any OAuth callback port (#{REDIRECT_PORTS.join(", ")})"
      end

      def build_server(port)
        @server_module::HTTPServer.new(
          BindAddress: "127.0.0.1",
          Port: port,
          Logger: @server_module::Log.new(File::NULL),
          AccessLog: []
        )
      end

      def load_server_module(library_loader)
        library_loader.call
        WEBrick
      rescue LoadError => e
        raise UnavailableError,
              "#{e.message}. To enable OAuth browser callbacks in downstream repos, add gem \"webrick\" to the Gemfile and run bundle install."
      end

      def mount_callback_handler
        @server.mount_proc "/oauth/callback" do |request, response|
          params = request.query.transform_keys(&:to_s)
          response["Content-Type"] = "text/html"

          if params["error"]
            response.status = 400
            response.body = error_page(params["error"], params["error_description"])
          else
            response.status = 200
            response.body = success_page
          end

          @callback = params
          @server.shutdown
        end
      end

      def success_page
        <<~HTML
          <!DOCTYPE html>
          <html><head><link rel="stylesheet" href="https://cdn.simplecss.org/simple.min.css"></head>
          <body><header><h1>Kennel Datadog OAuth</h1></header><h2>Authentication Successful</h2><p>You can close this window and return to kennel.</p></body></html>
        HTML
      end

      def error_page(error, description)
        <<~HTML
          <!DOCTYPE html>
          <html><head><link rel="stylesheet" href="https://cdn.simplecss.org/simple.min.css"></head>
          <body><header><h1>Kennel Datadog OAuth</h1></header><h2>Authentication Failed</h2><code>#{CGI.escapeHTML(error.to_s)}</code><p>#{CGI.escapeHTML(description.to_s)}</p></body></html>
        HTML
      end
    end
  end
end
