# frozen_string_literal: true
require_relative "../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered! uncovered: 37 # TODO: reduce this

describe "tasks" do
  with_env DATADOG_APP_KEY: "foo", DATADOG_API_KEY: "bar"

  def execute(env = {})
    with_env(env) { Rake::Task[task].execute }
  rescue SystemExit
    $!.status.must_equal 1
    raise "Aborted #{$!.message}"
  end

  capture_all

  let(:dump_output) do
    <<~TXT
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "foo": "bar",
        "api_resource": "dashboard"
      }
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "monitor"
      }
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "slo"
      }
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "synthetics/tests"
      }
    TXT
  end

  describe "kennel:nodata" do
    let(:task) { "kennel:nodata" }
    let(:monitors) do
      [{
        name: "Foo",
        id: 123,
        overall_state: "No Data",
        tags: []
      }]
    end

    before { Kennel.send(:api).stubs(:list).returns monitors }

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

  describe "kennel:dump" do
    in_temp_dir # uses file-cache

    let(:task) { "kennel:dump" }
    let(:api) { Kennel.send(:api) }

    before do
      list = [{ id: 1, modified_at: 2, name: "N" }]
      api.stubs(:list).returns list, deep_dup(list), deep_dup(list)
    end

    it "dumps" do
      execute(TYPE: "monitor")
      stdout.string.must_equal <<~JSON
        {
          "id": 1,
          "modified_at": 2,
          "name": "N",
          "api_resource": "monitor"
        }
      JSON
    end

    it "dumps all" do
      api.expects(:show).returns foo: "bar"
      execute
      stdout.string.must_equal dump_output
    end
  end

  describe "kennel:dump_grep" do
    in_temp_dir

    let(:task) { "kennel:dump_grep" }

    before { File.write("dump", dump_output) }

    it "can grep json" do
      with_env(DUMP: "dump", PATTERN: "foo") { execute }
      stdout.string.must_equal <<~JSON
        {
          "id": 1,
          "modified_at": 2,
          "name": "N",
          "foo": "bar",
          "api_resource": "dashboard"
        }
      JSON
    end

    it "can grep urls" do
      with_env(DUMP: "dump", PATTERN: "foo", URLS: "true") { execute }
      stdout.string.must_equal "/dashboard/1 # N\n"
    end

    it "fails when nothing matches" do
      e = assert_raises(RuntimeError) { with_env(DUMP: "dump", PATTERN: "nope") { execute } }
      e.message.must_equal "Aborted exit"
    end
  end

  describe "kennel:import" do
    let(:task) { "kennel:import" }

    it "can import from RESOURCE/ID" do
      Kennel::Importer.any_instance.expects(:import).with("monitor", 123).returns("X")
      execute(RESOURCE: "monitor", ID: "123")
      stdout.string.must_equal "X\n"
    end

    it "can import from URL" do
      Kennel::Importer.any_instance.expects(:import).with("dashboard", "abc").returns("X")
      execute(URL: "https://app.datadoghq.com/dashboard/abc")
      stdout.string.must_equal "X\n"
    end

    it "fails when neither is given" do
      e = assert_raises(RuntimeError) { execute(ID: "123") }
      e.message.must_equal "Aborted Call with URL= or call with RESOURCE=dashboard or monitor or slo or synthetics/tests and ID="
    end
  end
end
