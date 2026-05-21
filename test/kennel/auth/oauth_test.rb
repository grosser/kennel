# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Auth::OAuth do
  class FakeCallbackServer
    def self.redirect_uris
      ["http://127.0.0.1:8000/oauth/callback"]
    end
  end

  def valid_token(access_token: "token")
    Kennel::Auth::TokenSet.new(
      access_token: access_token,
      refresh_token: "refresh",
      token_type: "Bearer",
      expires_in: 3600,
      issued_at: Time.now.to_i,
      scope: "dashboards_read",
      client_id: "client"
    )
  end

  def expired_token
    Kennel::Auth::TokenSet.new(
      access_token: "expired",
      refresh_token: "refresh",
      token_type: "Bearer",
      expires_in: 60,
      issued_at: Time.now.to_i - 3600,
      scope: "dashboards_read",
      client_id: "client"
    )
  end

  def client_credentials
    Kennel::Auth::ClientCredentials.new(
      client_id: "client",
      client_name: "kennel",
      redirect_uris: FakeCallbackServer.redirect_uris,
      registered_at: Time.now.to_i,
      subdomain: "app",
      site: "datadoghq.com"
    )
  end

  it "applies a bearer token from storage" do
    store = mock
    store.stubs(:load_state).returns("token" => valid_token.to_h, "client" => client_credentials.to_h)
    oauth = Kennel::Auth::OAuth.new(token_store: store, callback_server_class: FakeCallbackServer, browser_launcher: ->(_url) {})
    request = Struct.new(:headers).new({})

    oauth.apply!(request)

    request.headers["Authorization"].must_equal "Bearer token"
  end

  it "refreshes expired tokens before applying them" do
    store = mock
    store.stubs(:load_state).returns("token" => expired_token.to_h, "client" => client_credentials.to_h)
    store.expects(:save_state).with do |state|
      state.fetch("token").fetch("access_token") == "fresh"
    end
    oauth = Kennel::Auth::OAuth.new(token_store: store, callback_server_class: FakeCallbackServer, browser_launcher: ->(_url) {})
    oauth.stubs(:request_tokens).returns(valid_token(access_token: "fresh"))
    request = Struct.new(:headers).new({})

    oauth.apply!(request)

    request.headers["Authorization"].must_equal "Bearer fresh"
  end

  it "builds an authorization url using the configured subdomain" do
    store = mock
    store.stubs(:load_state).returns({})
    oauth = Kennel::Auth::OAuth.new(
      site: "datadoghq.eu",
      subdomain: "acme",
      token_store: store,
      callback_server_class: FakeCallbackServer,
      browser_launcher: ->(_url) {}
    )
    challenge = Kennel::Auth::Pkce::Challenge.new(verifier: "v", challenge: "c", challenge_method: "S256")

    url = oauth.send(:authorization_url, "client", FakeCallbackServer.redirect_uris.first, "state", challenge)

    url.must_include "https://acme.datadoghq.eu/oauth2/v1/authorize"
    url.must_include "client_id=client"
    url.must_include "code_challenge=c"
  end

  it "registers the oauth client against the configured subdomain" do
    store = mock
    store.stubs(:load_state).returns({})
    oauth = Kennel::Auth::OAuth.new(
      site: "datadoghq.eu",
      subdomain: "acme",
      token_store: store,
      callback_server_class: FakeCallbackServer,
      browser_launcher: ->(_url) {}
    )

    stub_request(:post, "https://acme.datadoghq.eu/api/v2/oauth2/register")
      .to_return(
        status: 201,
        body: {
          client_id: "client",
          client_name: "kennel",
          redirect_uris: FakeCallbackServer.redirect_uris
        }.to_json
      )

    client = oauth.send(:register_client)

    client.client_id.must_equal "client"
    client.subdomain.must_equal "acme"
  end

  it "posts token exchanges against the configured subdomain" do
    store = mock
    store.stubs(:load_state).returns({})
    oauth = Kennel::Auth::OAuth.new(
      site: "datadoghq.eu",
      subdomain: "acme",
      token_store: store,
      callback_server_class: FakeCallbackServer,
      browser_launcher: ->(_url) {}
    )

    stub_request(:post, "https://acme.datadoghq.eu/oauth2/v1/token")
      .to_return(
        status: 200,
        body: {
          access_token: "token",
          refresh_token: "refresh",
          token_type: "Bearer",
          expires_in: 3600,
          scope: "dashboards_read"
        }.to_json
      )

    token = oauth.send(:request_tokens, { grant_type: "refresh_token", client_id: "client" }, "client")

    token.access_token.must_equal "token"
  end
end
