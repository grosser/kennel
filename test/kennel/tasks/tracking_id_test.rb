# frozen_string_literal: true
require_relative "../../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered!

describe "kennel:tracking_id" do
  enable_api
  capture_std

  it "finds tracking id" do
    get = stub_datadog_request(:get, "monitor/123").to_return(body: { message: "-- Managed by kennel foo:bar" }.to_json)
    execute_task ID: "123", RESOURCE: "monitor"
    stdout.string.must_equal "foo:bar\n"
    assert_requested get
  end
end
