# frozen_string_literal: true
require_relative "../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered! uncovered: 39 # TODO: reduce this

describe "tasks" do
  with_env DATADOG_APP_KEY: "foo", DATADOG_API_KEY: "bar"

  def execute(env = {})
    with_env(env) { Rake::Task[task].execute }
  rescue SystemExit
    $!.status.must_equal 1
    raise "Aborted #{$!.message}"
  end

  capture_all

  describe "kennel:nodata" do
    before { Kennel.send(:api).stubs(:list).returns monitors }

    let(:task) { "kennel:nodata" }
    let(:monitors) do
      [{
        name: "Foo",
        id: 123,
        overall_state: "No Data",
        tags: []
      }]
    end

    it "reports missing data" do
      execute TAG: "team:foo"
      stdout.string.must_equal "Foo\n/monitors/123\n\n"
      stderr.string.must_include "nodata:ignore"
    end

    it "stops without TAG" do
      e = assert_raises(RuntimeError) { execute }
      e.message.must_equal "Aborted Call with TAG=foo:bar"
    end

    it "ignores monitors with data" do
      monitors[0][:overall_state] = "OK"
      execute TAG: "team:foo"
      stdout.string.must_equal ""
    end

    it "ignores monitors marked as having no-data" do
      monitors[0][:tags] = ["nodata:ignore"]
      execute TAG: "team:foo"
      stdout.string.must_equal ""
    end
  end
end
