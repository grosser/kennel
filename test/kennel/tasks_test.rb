# frozen_string_literal: true
require_relative "../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered! uncovered: 22 # TODO: reduce this

main = self

# task tests do not call dependencies
describe "tasks" do
  def execute(env = {})
    with_env(env) { Rake::Task[task].execute }
  rescue SystemExit
    $!.status.must_equal 1
    raise "Aborted #{$!.message}"
  end

  enable_api
  capture_all

  let(:dump_output) do
    <<~TXT
      [
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "foo": "bar",
        "api_resource": "dashboard"
      },
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "monitor"
      },
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "slo"
      },
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "synthetics/tests"
      }
      ]
    TXT
  end
  let(:aborted) { Class.new(RuntimeError) }

  describe "kennel:nodata" do
    let(:task) { "kennel:nodata" }
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
      execute TAG: "team:foo"
      stdout.string.must_equal "Foo\nhttps://app.datadoghq.com/monitors/123\nNo data since 10d\n\n"
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

    describe "THRESHOLD_DAYS" do
      it "ignores recent no-data" do
        execute TAG: "team:foo", THRESHOLD_DAYS: "11"
        stdout.string.must_equal ""
      end

      it "keeps old no-data" do
        execute TAG: "team:foo", THRESHOLD_DAYS: "9"
        stdout.string.wont_equal ""
      end

      it "does not explode with missing date" do
        monitors[0].delete :overall_state_modified
        execute TAG: "team:foo", THRESHOLD_DAYS: "9"
        stdout.string.must_include " 999d"
      end
    end

    describe "json" do
      with_env FORMAT: "json"

      it "prints" do
        execute TAG: "team:foo"
        stdout.string.must_equal <<~JSON
          [
            {
              "url": "https://app.datadoghq.com/monitors/123",
              "name": "Foo",
              "tags": [

              ],
              "days_in_no_data": 10,
              "kennel_tracking_id": "a:b",
              "kennel_source": "a.rb"
            }
          ]
        JSON
      end

      it "does not crash on non-kennel monitors" do
        monitors[0][:message] = "HEY"
        execute TAG: "team:foo"
        stdout.string.must_include '"kennel_tracking_id": null'
        stdout.string.must_include '"kennel_source": null'
      end
    end
  end

  describe "kennel:dump" do
    in_temp_dir # uses file-cache

    let(:task) { "kennel:dump" }
    let(:api) { Kennel::Api.any_instance }

    before do
      list = [{ id: 1, modified_at: 2, name: "N" }]
      api.stubs(:list).returns list, deep_dup(list), deep_dup(list)
    end

    it "dumps" do
      execute(TYPE: "monitor")
      stdout.string.must_equal <<~JSON
        [
        {
          "id": 1,
          "modified_at": 2,
          "name": "N",
          "api_resource": "monitor"
        }
        ]
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
      stdout.string.must_equal "https://app.datadoghq.com/dashboard/1 # N\n"
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

  describe "kennel:tracking_id" do
    let(:task) { "kennel:tracking_id" }

    it "finds tracking id" do
      get = stub_datadog_request(:get, "monitor/123").to_return(body: { message: "-- Managed by kennel foo:bar" }.to_json)
      execute ID: "123", RESOURCE: "monitor"
      stdout.string.must_equal "foo:bar\n"
      assert_requested get
    end
  end

  describe "kennel:generate" do
    let(:task) { "kennel:generate" }

    it "runs" do
      Kennel::Engine.any_instance.expects(:generate)
      execute
    end
  end

  describe "kennel:no_diff" do
    let(:task) { "kennel:no_diff" }

    it "does not complain when there is no diff" do
      `true` # fake success signal
      main.expects(:`).returns ""
      execute
    end

    it "complains on diff" do
      `true` # fake success signal
      main.expects(:`).returns "foo"
      assert_raises { execute }.message.must_include "Aborted Diff found"
    end

    it "complains on error" do
      `false` # fake success signal
      main.expects(:`).returns ""
      assert_raises { execute }.message.must_include "Error during diffing"
    end
  end

  describe "kennel:validate_mentions" do
    let(:task) { "kennel:validate_mentions" }
    let(:content) { { message: "" } }

    def execute(...)
      Tempfile.create do |f|
        f.write(content.to_json)
        f.flush
        Dir.expects(:[]).returns([f.path])
        super
      end
    end

    before do
      Kennel::Api.any_instance.expects(:request).returns({ handles: { foo: [{ value: "bar" }, { value: "baz" }] } })
    end

    it "passes" do
      execute
    end

    it "ignores @here" do
      content[:message] = "@here"
      execute
    end

    it "ignores known bad" do
      content[:message] = "@oo@ps"
      execute KNOWN: "@oo@ps"
    end

    it "ignores non-monitors" do
      content.delete :message
      execute
    end

    it "fails when unknown mentions are used" do
      content[:message] = "@oo@ps"
      assert_raises { execute }.message.must_equal "Aborted SystemExit"
      stdout.string.downcase.must_include "invalid mentions"
    end
  end

  describe "kennel:plan" do
    let(:task) { "kennel:plan" }

    it "plans" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate)
      Kennel::Engine.any_instance.expects(:plan)
      execute
    end

    it "does not generate when asked" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate).never
      Kennel::Engine.any_instance.expects(:plan)
      execute KENNEL_NO_GENERATE: "true"
    end
  end

  describe "kennel:update_datadog" do
    let(:task) { "kennel:update_datadog" }

    it "updates" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate)
      Kennel::Engine.any_instance.expects(:update)
      execute
    end

    it "does not generate when asked" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate).never
      Kennel::Engine.any_instance.expects(:update)
      execute KENNEL_NO_GENERATE: "true"
    end
  end
end
