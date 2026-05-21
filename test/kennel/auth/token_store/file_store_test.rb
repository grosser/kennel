# frozen_string_literal: true
require_relative "../../../test_helper"

SingleCov.covered!

describe Kennel::Auth::TokenStore::FileStore do
  in_temp_dir

  it "defaults to a cache file in the user's home directory" do
    store = Kennel::Auth::TokenStore::FileStore.new(site: "datadoghq.com", subdomain: "app")

    store.file.must_equal File.expand_path("~/.kennel/oauth_auth.json")
  end

  it "stores state per site and subdomain in one file" do
    store = Kennel::Auth::TokenStore::FileStore.new(site: "datadoghq.com", subdomain: "app", file: "oauth.json")
    other = Kennel::Auth::TokenStore::FileStore.new(site: "datadoghq.com", subdomain: "acme", file: "oauth.json")
    store.save_state("token" => { "access_token" => "a" })
    other.save_state("token" => { "access_token" => "b" })
    store.load_state.must_equal("token" => { "access_token" => "a" })
    other.load_state.must_equal("token" => { "access_token" => "b" })
    JSON.parse(File.read("oauth.json")).keys.sort.must_equal ["datadoghq.com|acme", "datadoghq.com|app"]
  end

  it "loads legacy site-only app entries" do
    File.write("oauth.json", JSON.pretty_generate("datadoghq.com" => { "token" => { "access_token" => "a" } }))

    store = Kennel::Auth::TokenStore::FileStore.new(site: "datadoghq.com", subdomain: "app", file: "oauth.json")

    store.load_state.must_equal("token" => { "access_token" => "a" })
  end

  it "writes the file with secure permissions" do
    store = Kennel::Auth::TokenStore::FileStore.new(site: "datadoghq.com", subdomain: "app", file: "oauth.json")
    store.save_state("token" => { "access_token" => "a" })
    (File.stat("oauth.json").mode & 0o777).must_equal 0o600
  end
end
