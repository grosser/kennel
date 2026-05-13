# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Auth::TokenSet do
  it "roundtrips from hashes" do
    token = Kennel::Auth::TokenSet.new(
      access_token: "a",
      refresh_token: "r",
      token_type: "Bearer",
      expires_in: 3600,
      issued_at: Time.now.to_i,
      scope: "scope",
      client_id: "client"
    )

    parsed = Kennel::Auth::TokenSet.from_h(token.to_h)
    parsed.access_token.must_equal "a"
    parsed.refresh_token.must_equal "r"
    parsed.client_id.must_equal "client"
  end

  it "knows when a token is expired" do
    token = Kennel::Auth::TokenSet.new(
      access_token: "a",
      refresh_token: "r",
      token_type: "Bearer",
      expires_in: 60,
      issued_at: Time.now.to_i - 600,
      scope: "",
      client_id: "client"
    )

    token.expired?.must_equal true
  end
end

describe Kennel::Auth::ClientCredentials do
  it "roundtrips from hashes" do
    client = Kennel::Auth::ClientCredentials.new(
      client_id: "id",
      client_name: "kennel",
      redirect_uris: ["http://127.0.0.1:8000/oauth/callback"],
      registered_at: Time.now.to_i,
      subdomain: "acme",
      site: "datadoghq.com"
    )

    parsed = Kennel::Auth::ClientCredentials.from_h(client.to_h)
    parsed.client_id.must_equal "id"
    parsed.subdomain.must_equal "acme"
    parsed.site.must_equal "datadoghq.com"
  end

  it "defaults the subdomain for legacy hashes" do
    parsed = Kennel::Auth::ClientCredentials.from_h(
      "client_id" => "id",
      "client_name" => "kennel",
      "redirect_uris" => ["http://127.0.0.1:8000/oauth/callback"],
      "registered_at" => Time.now.to_i,
      "site" => "datadoghq.com"
    )

    parsed.subdomain.must_equal "app"
  end
end
