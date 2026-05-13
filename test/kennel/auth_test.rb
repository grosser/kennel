# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Auth do
  capture_std

  describe ".build" do
    it "uses static keys when configured" do
      with_env("DATADOG_APP_KEY" => "app", "DATADOG_API_KEY" => "api", "CI" => nil) do
        Kennel::Auth.build.must_be_instance_of Kennel::Auth::StaticKeys
        stderr.string.must_equal ""
      end
    end

    it "falls back to oauth when keys are missing" do
      with_env("DATADOG_APP_KEY" => nil, "DATADOG_API_KEY" => nil, "CI" => nil, "DD_TOKEN_STORAGE" => "file") do
        Kennel::Auth.build.must_be_instance_of Kennel::Auth::OAuth
        stderr.string.must_equal(
          "Warning: DATADOG_APP_KEY/DATADOG_API_KEY are not set, falling back to OAuth. Explicitly set DATADOG_AUTH_METHOD=oauth to silence this warning.\n"
        )
      end
    end

    it "uses oauth without warning when explicitly configured" do
      with_env(
        "DATADOG_APP_KEY" => "app",
        "DATADOG_API_KEY" => "api",
        "DATADOG_AUTH_METHOD" => "oauth",
        "CI" => nil,
        "DD_TOKEN_STORAGE" => "file"
      ) do
        Kennel::Auth.build.must_be_instance_of Kennel::Auth::OAuth
        stderr.string.must_equal ""
      end
    end

    it "uses static auth when explicitly configured" do
      with_env("DATADOG_APP_KEY" => "app", "DATADOG_API_KEY" => "api", "DATADOG_AUTH_METHOD" => "static", "CI" => nil) do
        Kennel::Auth.build.must_be_instance_of Kennel::Auth::StaticKeys
        stderr.string.must_equal ""
      end
    end

    it "fails when static auth is forced without keys" do
      with_env("DATADOG_APP_KEY" => nil, "DATADOG_API_KEY" => nil, "DATADOG_AUTH_METHOD" => "static", "CI" => nil) do
        error = assert_raises(RuntimeError) { Kennel::Auth.build }
        error.message.must_equal "DATADOG_AUTH_METHOD=static requires DATADOG_APP_KEY and DATADOG_API_KEY"
      end
    end

    it "fails on unknown auth methods" do
      with_env("DATADOG_AUTH_METHOD" => "wat", "CI" => nil) do
        error = assert_raises(RuntimeError) { Kennel::Auth.build }
        error.message.must_equal 'Unknown DATADOG_AUTH_METHOD="wat", expected static or oauth'
      end
    end

    it "fails on ci when neither auth mode is configured" do
      with_env("DATADOG_APP_KEY" => nil, "DATADOG_API_KEY" => nil, "CI" => "true") do
        assert_raises(RuntimeError) { Kennel::Auth.build }
      end
    end

    it "uses oauth on ci when explicitly configured" do
      with_env("DATADOG_AUTH_METHOD" => "oauth", "DATADOG_APP_KEY" => nil, "DATADOG_API_KEY" => nil, "CI" => "true") do
        Kennel::Auth.build.must_be_instance_of Kennel::Auth::OAuth
      end
    end
  end
end
