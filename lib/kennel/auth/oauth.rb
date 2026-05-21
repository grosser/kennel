# frozen_string_literal: true

require "cgi"

module Kennel
  module Auth
    class OAuth
      CLIENT_NAME = "datadog-pup-cli" # we must pretend to be pup to get the right scopes without manual approval
      DEFAULT_SCOPES = %w[
        dashboards_read
        dashboards_write
        monitors_read
        monitors_write
        monitors_downtime
        slos_read
        slos_write
        synthetics_read
        synthetics_write
      ].freeze

      def self.scopes_from_env
        if (raw = Utils.presence(ENV["DD_OAUTH_SCOPES"]))
          raw.split(/[\s,]+/).reject(&:empty?)
        else
          DEFAULT_SCOPES
        end
      end

      def initialize(
        site: ENV.fetch("DD_SITE", "datadoghq.com"),
        subdomain: Utils.presence(ENV["DATADOG_SUBDOMAIN"]) || "app",
        scopes: self.class.scopes_from_env,
        token_store: TokenStore.build(site: site, subdomain: subdomain),
        callback_server_class: CallbackServer,
        browser_launcher: nil,
        org_uuid: Utils.presence(ENV["DD_OAUTH_ORG_UUID"])
      )
        @site = site
        @subdomain = subdomain
        @scopes = scopes
        @token_store = token_store
        @callback_server_class = callback_server_class
        @browser_launcher = browser_launcher || method(:open_browser)
        @org_uuid = org_uuid
      end

      def apply!(request)
        token = ensure_token
        request.headers["Authorization"] = "#{token.token_type} #{token.access_token}"
      end

      def prepare!
        ensure_token
        true
      end

      def invalidate!
        @load_state = nil
        true
      end

      def refresh!
        ensure_token(force_refresh: true)
        true
      end

      private

      attr_reader :site, :subdomain, :scopes

      def ensure_token(force_refresh: false)
        token = force_refresh ? nil : load_token
        return token if token && !token.expired?

        client = load_client || register_client
        token ||= load_token

        token =
          if token&.refresh_token.to_s == ""
            login(client)
          else
            refresh_token(token, client)
          end

        persist_state(token: token, client: client)
        token
      end

      def load_state
        @load_state ||= @token_store.load_state
      end

      def load_token
        TokenSet.from_h(load_state["token"])
      end

      def load_client
        ClientCredentials.from_h(load_state["client"])
      end

      def persist_state(token:, client:)
        @load_state = {}
        @load_state["client"] = client.to_h if client
        @load_state["token"] = token.to_h if token
        @token_store.save_state(@load_state)
      end

      def register_client
        response = Faraday.post(oauth_url("/api/v2/oauth2/register")) do |request|
          request.headers["Content-type"] = "application/json"
          request.body = JSON.generate(
            client_name: CLIENT_NAME,
            redirect_uris: @callback_server_class.redirect_uris,
            grant_types: ["authorization_code", "refresh_token"]
          )
        end

        unless response.status == 201
          raise "DCR registration failed (HTTP #{response.status}): #{response.body}"
        end

        body = JSON.parse(response.body)

        ClientCredentials.new(
          client_id: body.fetch("client_id"),
          client_name: body.fetch("client_name", CLIENT_NAME),
          redirect_uris: body.fetch("redirect_uris", @callback_server_class.redirect_uris),
          registered_at: Time.now.to_i,
          subdomain: subdomain,
          site: site
        )
      end

      def refresh_token(token, client)
        request_tokens(
          {
            grant_type: "refresh_token",
            client_id: client.client_id,
            refresh_token: token.refresh_token
          },
          client.client_id
        )
      rescue RuntimeError
        login(client)
      end

      def login(client)
        callback_server = @callback_server_class.new(pinned_port: callback_port)
        challenge = Pkce.generate_challenge
        state = Pkce.generate_state
        url = authorization_url(client.client_id, callback_server.redirect_uri, state, challenge)

        @browser_launcher.call(url)
        Kennel.err.puts "Complete OAuth login in your browser if it did not open automatically:\n#{url}"

        callback = callback_server.wait_for_callback(timeout: 300)
        if callback["error"]
          raise "OAuth authorization failed: #{callback["error"]} #{callback["error_description"]}".strip
        end
        raise "OAuth state mismatch" unless callback["state"] == state

        request_tokens(
          {
            grant_type: "authorization_code",
            client_id: client.client_id,
            code: callback.fetch("code"),
            redirect_uri: callback_server.redirect_uri,
            code_verifier: challenge.verifier
          },
          client.client_id
        )
      ensure
        callback_server&.close
      end

      def request_tokens(params, client_id)
        response = Faraday.post(oauth_url("/oauth2/v1/token")) do |request|
          request.headers["Content-type"] = "application/x-www-form-urlencoded"
          request.body = URI.encode_www_form(params)
        end

        unless response.success?
          raise "token exchange failed (HTTP #{response.status}): #{response.body}"
        end

        body = JSON.parse(response.body)
        TokenSet.new(
          access_token: body.fetch("access_token"),
          refresh_token: body.fetch("refresh_token", ""),
          token_type: body.fetch("token_type", "Bearer"),
          expires_in: body.fetch("expires_in"),
          issued_at: Time.now.to_i,
          scope: body.fetch("scope", ""),
          client_id: client_id
        )
      end

      def authorization_url(client_id, redirect_uri, state, challenge)
        params = {
          response_type: "code",
          client_id: client_id,
          redirect_uri: redirect_uri,
          state: state,
          scope: scopes.sort.join(" "),
          code_challenge: challenge.challenge,
          code_challenge_method: challenge.challenge_method
        }
        params[:dd_oid] = @org_uuid if @org_uuid
        "https://#{subdomain}.#{site}/oauth2/v1/authorize?#{URI.encode_www_form(params)}"
      end

      def callback_port
        raw = Utils.presence(ENV["DD_OAUTH_CALLBACK_PORT"])
        return unless raw

        Integer(raw)
      end

      def oauth_url(path)
        "https://#{subdomain}.#{site}#{path}"
      end

      def open_browser(url)
        system("open", url) || system("xdg-open", url)
      end
    end
  end
end
