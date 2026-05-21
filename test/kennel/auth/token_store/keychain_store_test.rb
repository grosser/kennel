# frozen_string_literal: true
require_relative "../../../test_helper"

SingleCov.covered!

describe Kennel::Auth::TokenStore::KeychainStore do
  it "raises unavailable when the optional keychain gem is missing" do
    error = assert_raises(Kennel::Auth::TokenStore::KeychainStore::UnavailableError) do
      Kennel::Auth::TokenStore::KeychainStore.new(
        site: "datadoghq.com",
        subdomain: "app",
        library_loader: -> { raise LoadError, "missing" }
      )
    end

    error.message.must_include "missing"
  end
end
