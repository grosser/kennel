# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Monitor do
  class TestMonitor < Kennel::Models::Monitor
  end

  # generate readables diffs when things are not equal
  def assert_json_equal(a, b)
    JSON.pretty_generate(a).must_equal JSON.pretty_generate(b)
  end

  def monitor(options = {})
    Kennel::Models::Monitor.new(
      options.delete(:project) || project,
      {
        type: -> { "query alert" },
        kennel_id: -> { "m1" },
        query: -> { "avg(last_5m) > #{critical}" },
        critical: -> { 123.0 }
      }.merge(options)
    )
  end

  let(:project) { TestProject.new }
  let(:expected_basic_json) do
    {
      name: "Kennel::Models::Monitor\u{1F512}",
      type: "query alert",
      query: +"avg(last_5m) > 123.0",
      message: "@slack-foo",
      tags: ["service:test_project", "team:test_team"],
      options: {
        timeout_h: 0,
        notify_no_data: true,
        no_data_timeframe: 60,
        notify_audit: true,
        require_full_window: true,
        new_host_delay: 300,
        include_tags: true,
        escalation_message: nil,
        evaluation_delay: nil,
        locked: false,
        renotify_interval: 120,
        thresholds: { critical: 123.0 }
      }
    }
  end

  describe "#initialize" do
    it "stores project" do
      TestMonitor.new(111).project.must_equal 111
    end

    it "stores options" do
      TestMonitor.new(111, name: -> { "XXX" }).name.must_equal "XXX"
    end
  end

  describe "#as_json" do
    it "creates a basic json" do
      assert_json_equal(
        monitor.as_json,
        expected_basic_json
      )
    end

    it "can set warning" do
      monitor(warning: -> { 123.0 }).as_json.dig(:options, :thresholds, :warning).must_equal 123.0
    end

    it "can set timeout_h" do
      monitor(timeout_h: -> { 1 }).as_json.dig(:options, :timeout_h).must_equal 1
    end

    it "does not call optional methods twice" do
      called = 0
      monitor(warning: -> { called += 1 }).as_json
      called.must_equal 1
    end

    it "can set warning_recovery" do
      monitor(warning_recovery: -> { 123.0 }).as_json.dig(:options, :thresholds, :warning_recovery).must_equal 123.0
    end

    it "can set critical_recovery" do
      monitor(critical_recovery: -> { 123.0 }).as_json.dig(:options, :thresholds, :critical_recovery).must_equal 123.0
    end

    it "adds project tags" do
      monitor(project: TestProject.new(tags: -> { ["foo"] })).as_json[:tags].must_equal(["foo"])
    end

    it "sets 0 when re-notify is disabled" do
      monitor(renotify_interval: -> { false }).as_json[:options][:renotify_interval].must_equal 0
    end

    it "can set require_full_window" do
      monitor(require_full_window: -> { true }).as_json[:options][:require_full_window].must_equal true
    end

    describe "query alert" do
      it "converts threshold values to floats to avoid api diff" do
        monitor(critical: -> { 234 }).as_json
          .dig(:options, :thresholds, :critical).must_equal 234.0
      end

      it "does not converts threshold values to floats for types that store integers" do
        monitor(critical: -> { 234 }, type: -> { "service check" }).as_json
          .dig(:options, :thresholds, :critical).must_equal 234
      end
    end

    it "does not set thresholds for composite monitors" do
      json = monitor(critical: -> { raise }, query: -> { "1 || 2" }, type: -> { "composite" }).as_json
      refute json[:options].key?(:thresholds)
    end

    it "fills default values for service check ok/warning" do
      json = monitor(critical: -> { 234 }, type: -> { "service check" }).as_json
      json.dig(:options, :thresholds, :ok).must_equal 1
      json.dig(:options, :thresholds, :warning).must_equal 1
    end

    it "fails when using invalid interval for query alert type" do
      e = assert_raises(RuntimeError) { monitor(critical: -> { 234.1 }, query: -> { "avg(last_20m).count() < #{critical}" }).as_json }
      e.message.must_equal "test_project:m1 query interval was 20m, but must be one of 1m, 5m, 10m, 15m, 30m, 1h, 2h, 4h, 1d"
    end

    it "allows next_x interval for query alert type" do
      monitor(critical: -> { 234.1 }, query: -> { "avg(next_20m).count() < #{critical}" }).as_json
    end

    it "does not allow mismatching query and critical" do
      e = assert_raises(RuntimeError) { monitor(critical: -> { 123.0 }, query: -> { "foo < 12" }).as_json }
      e.message.must_equal "test_project:m1 critical and value used in query must match"
    end

    it "does not allow mismatching query and critical with >=" do
      e = assert_raises(RuntimeError) { monitor(critical: -> { 123.0 }, query: -> { "foo <= 12" }).as_json }
      e.message.must_equal "test_project:m1 critical and value used in query must match"
    end

    it "does not break on queries that are unparseable for critical" do
      monitor(critical: -> { 123.0 }, query: -> { "(last_5m) foo = 12" }).as_json
    end

    it "fails on invalid renotify intervals" do
      e = assert_raises(RuntimeError) { monitor(renotify_interval: -> { 123 }).as_json }
      e.message.must_include "test_project:m1 renotify_interval must be one of 0, 10, 20,"
    end

    it "sets no_data_timeframe to `nil` when notify_no_data is false" do
      monitor(notify_no_data: -> { false }).as_json[:options][:no_data_timeframe].must_be_nil
    end

    it "can set notify_audit" do
      monitor(notify_audit: -> { false }).as_json.dig(:options, :notify_audit).must_equal false
    end

    it "is cached so we can modify it in syncer" do
      m = monitor
      m.as_json[:foo] = 1
      m.as_json[:foo].must_equal 1
    end

    it "fails on deprecated metric alert type" do
      e = assert_raises(RuntimeError) { monitor(type: -> { "metric alert" }).as_json }
      e.message.must_include "metric alert"
    end

    it "does not fail when validations are disabled" do
      monitor(type: -> { "metric alert" }, validate: -> { false }).as_json
    end

    it "sets id when not given" do
      assert_json_equal(
        monitor(id: -> { 123 }).as_json,
        expected_basic_json.merge(id: 123)
      )
    end

    it "strips query to avoid perma-diff" do
      monitor(query: -> { " avg(last_5m) > 123.0 " }).as_json.dig(:query).must_equal "avg(last_5m) > 123.0"
    end

    it "can set slack on the project" do
      monitor(project: TestProject.new(slack: -> { "project" })).as_json[:message].must_equal "@slack-project"
    end

    it "can set evaluation_delay" do
      monitor(evaluation_delay: -> { 20 }).as_json.dig(:options, :evaluation_delay).must_equal 20
    end

    it "can set new_host_delay" do
      monitor(new_host_delay: -> { 300 }).as_json.dig(:options, :new_host_delay).must_equal 300
    end

    it "can set threshold_windows" do
      monitor(threshold_windows: -> { 20 }).as_json.dig(:options, :threshold_windows).must_equal 20
    end

    # happens when project/team have the same tags and they double up
    it "only sets tags once to avoid perma-diff when datadog unqiues them" do
      monitor(tags: -> { ["a", "b", "a"] }).as_json[:tags].must_equal ["a", "b"]
    end

    describe "is_match validation" do
      let(:mon) { monitor(query: -> { "avg(last_5m):avg:foo by {env} > 123.0" }) }

      it "passes without is_match" do
        mon.as_json
      end

      it "fails when using invalid is_match" do
        mon.stubs(:message).returns('{{#is_match "environment.name" "production"}}TEST{{/is_match}}')
        e = assert_raises(RuntimeError) { mon.as_json }
        e.message.must_equal "test_project:m1 is_match used with unsupported dimensions [\"environment\"], allowed dimensions are [\"env\"]"
      end

      it "passes when using valid is_match" do
        mon.expects(:message).returns('{{#is_match "env.name" "production"}}TEST{{/is_match}}')
        mon.as_json
      end
    end
  end

  describe "#resolve_linked_tracking_ids" do
    let(:mon) do
      monitor(query: -> { "%{#{project.kennel_id}:mon}" })
    end

    it "does nothing for regular monitors" do
      mon.resolve_linked_tracking_ids({})
      mon.as_json[:query].must_equal "%{#{project.kennel_id}:mon}"
    end

    describe "composite monitor" do
      let(:mon) do
        monitor(type: -> { "composite" }, query: -> { "%{#{project.kennel_id}:mon}" })
      end

      it "does not fail hard when matching monitor is missing" do
        err = Kennel::Utils.capture_stderr do
          mon.resolve_linked_tracking_ids({})
          mon.as_json[:query].must_equal("%{#{project.kennel_id}:mon}")
        end
        err.must_include "Unable to find #{project.kennel_id}:mon in existing monitors"
      end

      it "resolves correctly with a matching monitor" do
        mon.resolve_linked_tracking_ids("#{project.kennel_id}:mon" => 42)
        mon.as_json[:query].must_equal("42")
      end
    end
  end

  describe "#diff" do
    # minitest defines diff, do not override it
    def diff_resource(e, a)
      a = expected_basic_json.merge(a)
      a[:options] = expected_basic_json[:options].merge(a[:options] || {})
      monitor(e).diff(a)
    end

    it "calls super" do
      diff_resource({}, deleted: true).must_equal []
    end

    it "ignores silenced" do
      diff_resource({}, options: { silenced: true }).must_equal []
    end

    it "ignores missing evaluation_delay" do
      expected_basic_json[:options].delete(:evaluation_delay)
      diff_resource({}, {}).must_equal []
    end

    it "ignores include_tags/require_full_window for service alerts" do
      assert expected_basic_json[:query].sub!("123.0", "123")
      expected_basic_json[:options].delete(:include_tags)
      expected_basic_json[:options].delete(:require_full_window)
      expected_basic_json[:options][:thresholds][:critical] = 123
      diff_resource(
        {
          type: -> { "service check" },
          critical: -> { 123 },
          warning: -> { 1 },
          ok: -> { 1 }
        },
        type: "service check",
        multi: true
      ).must_equal []
    end

    it "ignores missing critical from event alert" do
      assert expected_basic_json[:query].sub!("123.0", "0")
      expected_basic_json[:options].delete(:thresholds)
      expected_basic_json[:options][:require_full_window] = true
      diff_resource(
        {
          type: -> { "event alert" },
          critical: -> { 0 }
        },
        type: "event alert",
        multi: true
      ).must_equal []
    end

    it "ignores type diff between metric and query since datadog uses both randomly" do
      diff_resource({ type: -> { "query alert" } }, {}).must_equal []
    end

    describe "#escalation_message" do
      it "ignores missing escalation_message" do
        expected_basic_json[:options].delete(:escalation_message)
        diff_resource({}, {}).must_equal []
      end

      it "ignores blank escalation_message" do
        expected_basic_json[:options][:escalation_message] = ""
        diff_resource({}, {}).must_equal []
      end

      it "keeps existing escalation_message" do
        expected_basic_json[:options][:escalation_message] = "keep me"
        diff_resource({}, {}).must_equal [["~", "options.escalation_message", "keep me", nil]]
      end
    end
  end

  describe "#url" do
    it "shows path" do
      monitor.url(111).must_equal "/monitors#111/edit"
    end

    it "shows full url" do
      with_env DATADOG_SUBDOMAIN: "foobar" do
        monitor.url(111).must_equal "https://foobar.datadoghq.com/monitors#111/edit"
      end
    end
  end

  describe ".api_resource" do
    it "is set" do
      Kennel::Models::Monitor.api_resource.must_equal "monitor"
    end
  end

  describe ".normalize" do
    it "works with empty" do
      Kennel::Models::Monitor.normalize({}, options: {})
    end

    it "does not ignore notify_audit/notify_no_data since that would make import incorrect" do
      actual = { options: { notify_audit: false, notify_no_data: false } }
      expected = { options: { notify_audit: false, notify_no_data: false } }
      Kennel::Models::Monitor.normalize(expected, actual)
      expected.must_equal(options: { notify_audit: false, notify_no_data: false })
      actual.must_equal(options: { notify_audit: false, notify_no_data: false })
    end

    it "ignores defaults" do
      actual = { options: { timeout_h: 0 } }
      expected = { options: { timeout_h: 0 } }
      Kennel::Models::Monitor.normalize(expected, actual)
      expected.must_equal(options: {})
      actual.must_equal(options: {})
    end
  end

  describe "#require_full_window" do
    it "is true for on_average query" do
      assert monitor.as_json.dig(:options, :require_full_window)
    end

    it "is true for at_all_times query" do
      assert monitor(query: -> { "min(last_5m) > #{critical}" }).as_json.dig(:options, :require_full_window)
    end

    it "is true for in_total query" do
      assert monitor(query: -> { "sum(last_5m) > #{critical}" }).as_json.dig(:options, :require_full_window)
    end

    it "is false for at_least_once query" do
      refute monitor(query: -> { "max(last_5m) > #{critical}" }).as_json.dig(:options, :require_full_window)
    end

    it "is true for non-query" do
      assert monitor(type: -> { "foo bar" }).as_json.dig(:options, :require_full_window)
    end
  end
end
