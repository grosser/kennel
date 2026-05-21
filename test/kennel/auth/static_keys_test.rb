# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Auth::StaticKeys do
  describe ".configured?" do
    it "is true when both keys are set" do
      with_env("DATADOG_APP_KEY" => "app", "DATADOG_API_KEY" => "api") do
        assert Kennel::Auth::StaticKeys.configured?
      end
    end

    it "is false when keys are missing" do
      with_env("DATADOG_APP_KEY" => nil, "DATADOG_API_KEY" => nil) do
        assert_nil Kennel::Auth::StaticKeys.configured?
      end
    end
  end

  describe "#apply!" do
    it "sets DD headers on the request" do
      auth = Kennel::Auth::StaticKeys.new(app_key: "app", api_key: "api")
      request = Struct.new(:headers).new({})

      auth.apply!(request)

      request.headers["DD-API-KEY"].must_equal "api"
      request.headers["DD-APPLICATION-KEY"].must_equal "app"
    end
  end

  describe "#prepare!" do
    it "returns true" do
      Kennel::Auth::StaticKeys.new(app_key: "a", api_key: "b").prepare!.must_equal true
    end
  end

  describe "#invalidate!" do
    it "returns false" do
      Kennel::Auth::StaticKeys.new(app_key: "a", api_key: "b").invalidate!.must_equal false
    end
  end

  describe "#refresh!" do
    it "returns false" do
      Kennel::Auth::StaticKeys.new(app_key: "a", api_key: "b").refresh!.must_equal false
    end
  end
end
