# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Auth::TokenStore do
  let(:stderr) { StringIO.new }

  it "uses file storage when requested" do
    with_env("DD_TOKEN_STORAGE" => "file") do
      Kennel::Auth::TokenStore.build(site: "datadoghq.com", subdomain: "app", err: stderr).must_be_instance_of Kennel::Auth::TokenStore::FileStore
    end
  end

  it "fails when keychain is explicitly requested but unavailable" do
    with_env("DD_TOKEN_STORAGE" => "keychain") do
      Kennel::Auth::TokenStore::KeychainStore.expects(:new).with(site: "datadoghq.com", subdomain: "app").raises(
        Kennel::Auth::TokenStore::KeychainStore::UnavailableError, "missing"
      )
      assert_raises(Kennel::Auth::TokenStore::KeychainStore::UnavailableError) do
        Kennel::Auth::TokenStore.build(site: "datadoghq.com", subdomain: "app", err: stderr)
      end
    end
  end

  it "falls back to file storage when keychain is unavailable" do
    with_env("DD_TOKEN_STORAGE" => nil) do
      Kennel::Auth::TokenStore::KeychainStore.expects(:new).with(site: "datadoghq.com", subdomain: "app").raises(
        Kennel::Auth::TokenStore::KeychainStore::UnavailableError, "missing"
      )
      Kennel::Auth::TokenStore.build(site: "datadoghq.com", subdomain: "app", err: stderr).must_be_instance_of Kennel::Auth::TokenStore::FileStore
      stderr.string.must_include 'add gem "ruby-keychain" to the Gemfile and run bundle install'
      stderr.string.must_include File.expand_path("~/.kennel/oauth_auth.json")
      stderr.string.must_include "chmod 0600"
      stderr.string.must_include "access and refresh tokens on disk"
    end
  end

  it "switches to the fallback store after a keychain failure" do
    primary = mock
    primary.expects(:load_state).raises(Kennel::Auth::TokenStore::KeychainStore::StoreError, "boom")
    fallback = Kennel::Auth::TokenStore::FileStore.new(site: "datadoghq.com", subdomain: "app", file: "tmp/cache/oauth_auth.json")
    fallback.expects(:load_state).returns({})

    store = Kennel::Auth::TokenStore::Fallback.new(primary: primary, fallback: fallback, err: stderr)
    store.load_state.must_equal({})
    stderr.string.must_include 'add gem "ruby-keychain" to the Gemfile and run bundle install'
  end

  it "switches to the fallback store for saves and only warns once" do
    primary = Object.new
    primary.define_singleton_method(:save_state) do |_state|
      raise Kennel::Auth::TokenStore::KeychainStore::StoreError, "boom"
    end

    saved = []
    fallback = Object.new
    fallback.define_singleton_method(:file) { "tmp/cache/oauth_auth.json" }
    fallback.define_singleton_method(:save_state) { |state| saved << state }
    fallback.define_singleton_method(:load_state) { {} }

    store = Kennel::Auth::TokenStore::Fallback.new(primary: primary, fallback: fallback, err: stderr)
    store.save_state("token" => { "access_token" => "a" })
    store.load_state.must_equal({})
    saved.must_equal [{ "token" => { "access_token" => "a" } }]
    stderr.string.scan(/Keychain unavailable|Keychain failed/).size.must_equal 1
  end

  it "describes the file fallback risk in the warning helper" do
    file_store = Kennel::Auth::TokenStore::FileStore.new(site: "datadoghq.com", subdomain: "app", file: "tmp/cache/oauth_auth.json")

    warning = Kennel::Auth::TokenStore.fallback_warning("missing", file_store)

    warning.must_include 'add gem "ruby-keychain" to the Gemfile and run bundle install'
    warning.must_include "tmp/cache/oauth_auth.json"
    warning.must_include "chmod 0600"
    warning.must_include "access and refresh tokens on disk"
  end

  it "does not warn again after the first fallback warning" do
    primary = Object.new
    primary.define_singleton_method(:load_state) do
      raise Kennel::Auth::TokenStore::KeychainStore::StoreError, "primary boom"
    end

    load_calls = 0
    fallback = Object.new
    fallback.define_singleton_method(:file) { "tmp/cache/oauth_auth.json" }
    fallback.define_singleton_method(:load_state) do
      load_calls += 1
      raise Kennel::Auth::TokenStore::KeychainStore::StoreError, "fallback boom" if load_calls == 2

      {}
    end

    store = Kennel::Auth::TokenStore::Fallback.new(primary: primary, fallback: fallback, err: stderr)
    store.load_state.must_equal({})
    store.load_state.must_equal({})
    stderr.string.scan(/Keychain unavailable|Keychain failed/).size.must_equal 1
  end
end
