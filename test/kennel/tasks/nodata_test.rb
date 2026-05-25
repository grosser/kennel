# frozen_string_literal: true
require_relative "../../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered!

describe "kennel:nodata" do
  enable_api
  capture_std

  let(:monitors) do
    [{
      name: "Foo",
      id: 123,
      overall_state: "No Data",
      message: "Foo bar -- Managed by kennel a:b in a.rb, foo bar",
      tags: [],
      overall_state_modified: (Time.now - (10 * 24 * 60 * 60)).to_s
    }]
  end

  before { Kennel::Api.any_instance.stubs(:list).returns monitors }

  it "reports missing data" do
    execute_task TAG: "team:foo"
    stdout.string.must_equal "Foo\nhttps://app.datadoghq.com/monitors/123\nNo data since 10d\n\n"
    stderr.string.must_include "nodata:ignore"
  end

  it "stops without TAG" do
    e = assert_raises(RuntimeError) { execute_task }
    e.message.must_equal "Aborted Call with TAG=foo:bar"
  end

  it "ignores monitors with data" do
    monitors[0][:overall_state] = "OK"
    execute_task TAG: "team:foo"
    stdout.string.must_equal ""
  end

  it "ignores monitors marked as having no-data" do
    monitors[0][:tags] = ["nodata:ignore"]
    execute_task TAG: "team:foo"
    stdout.string.must_equal ""
  end

  describe "THRESHOLD_DAYS" do
    it "ignores recent no-data" do
      execute_task TAG: "team:foo", THRESHOLD_DAYS: "11"
      stdout.string.must_equal ""
    end

    it "keeps old no-data" do
      execute_task TAG: "team:foo", THRESHOLD_DAYS: "9"
      stdout.string.wont_equal ""
    end

    it "does not explode with missing date" do
      monitors[0].delete :overall_state_modified
      execute_task TAG: "team:foo", THRESHOLD_DAYS: "9"
      stdout.string.must_include " 999d"
    end
  end

  describe "json" do
    with_env FORMAT: "json"

    it "prints" do
      execute_task TAG: "team:foo"
      stdout.string.must_equal <<~JSON
        [
          {
            "url": "https://app.datadoghq.com/monitors/123",
            "name": "Foo",
            "tags": [],
            "days_in_no_data": 10,
            "kennel_tracking_id": "a:b",
            "kennel_source": "a.rb"
          }
        ]
      JSON
    end

    it "does not crash on non-kennel monitors" do
      monitors[0][:message] = "HEY"
      execute_task TAG: "team:foo"
      stdout.string.must_include '"kennel_tracking_id": null'
      stdout.string.must_include '"kennel_source": null'
    end
  end
end
