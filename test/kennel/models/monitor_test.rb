# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Monitor do
  define_test_classes

  class TestMonitor < Kennel::Models::Monitor
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
  let(:id_map) { Kennel::IdMap.new }
  let(:expected_basic_json) do
    {
      name: "Kennel::Models::Monitor\u{1F512}",
      type: "query alert",
      query: +"avg(last_5m) > 123.0",
      message: "@slack-foo",
      tags: ["team:test-team"],
      priority: nil,
      options: {
        timeout_h: 0,
        notify_no_data: true,
        no_data_timeframe: 60,
        notify_audit: false,
        require_full_window: false,
        new_host_delay: 300,
        include_tags: true,
        escalation_message: nil,
        evaluation_delay: nil,
        renotify_interval: 0,
        thresholds: { critical: 123.0 },
        variables: nil
      }
    }
  end

  describe "#initialize" do
    it "stores project" do
      TestMonitor.new(project).project.must_equal project
    end

    it "stores options" do
      TestMonitor.new(project, name: -> { "XXX" }).name.must_equal "XXX"
    end
  end

  describe "#build_json" do
    def valid_monitor_json(...)
      m = monitor(...)
      validation_errors_from(m).must_equal []
      m.as_json
    end

    it "creates a basic json" do
      assert_json_equal(
        valid_monitor_json,
        expected_basic_json
      )
    end

    it "can set warning" do
      valid_monitor_json(warning: -> { 1.2 }).dig(:options, :thresholds, :warning).must_equal 1.2
    end

    it "can set timeout_h" do
      valid_monitor_json(timeout_h: -> { 1 }).dig(:options, :timeout_h).must_equal 1
    end

    it "does not call optional methods twice" do
      called = 0
      valid_monitor_json(warning: -> { called += 1 })
      called.must_equal 1
    end

    it "can set warning_recovery" do
      valid_monitor_json(warning_recovery: -> { 123.0 }).dig(:options, :thresholds, :warning_recovery).must_equal 123.0
    end

    it "can set critical_recovery" do
      valid_monitor_json(critical_recovery: -> { 123.0 }).dig(:options, :thresholds, :critical_recovery).must_equal 123.0
    end

    it "adds project tags" do
      valid_monitor_json(project: TestProject.new(tags: -> { ["foo"] }))[:tags].must_equal(["foo"])
    end

    it "can set require_full_window" do
      valid_monitor_json(require_full_window: -> { true })[:options][:require_full_window].must_equal true
    end

    it "can set variables" do
      valid_monitor_json(variables: -> { { a: 1 } })[:options][:variables].must_equal a: 1
    end

    describe "query alert" do
      it "converts threshold values to floats to avoid api diff" do
        valid_monitor_json(critical: -> { 234 })
          .dig(:options, :thresholds, :critical).must_equal 234.0
      end

      it "does not converts threshold values to floats for types that store integers" do
        valid_monitor_json(critical: -> { 234 }, type: -> { "service check" }, query: -> { "foo.by(x)" })
          .dig(:options, :thresholds, :critical).must_equal 234
      end
    end

    describe "notify_by" do
      it "can set notify_by" do
        valid_monitor_json(notify_by: -> { ["*"] })[:options][:notify_by].must_equal ["*"]
      end

      it "does not set when nil to avoid diff" do
        refute valid_monitor_json[:options].key? :notify_by
      end
    end

    it "does not set thresholds for composite monitors" do
      json = monitor(
        critical: -> { raise },
        query: -> { "1 || 2" },
        type: -> { "composite" },
        ignored_errors: [:links_must_be_via_tracking_id]
      ).build_json
      refute json[:options].key?(:thresholds)
    end

    it "fills default values for service check ok/warning" do
      json = valid_monitor_json(critical: -> { 234 }, type: -> { "service check" }, query: -> { "foo.by(x)" })
      json.dig(:options, :thresholds, :ok).must_equal 1
      json.dig(:options, :thresholds, :warning).must_equal 1
    end

    it "allows next_x interval for query alert type" do
      valid_monitor_json(critical: -> { 234.1 }, query: -> { "avg(next_20m).count() < #{critical}" })
    end

    it "does not allow mismatching query and critical" do
      validation_errors_from(monitor(critical: -> { 123.0 }, query: -> { "foo < 12" }))
        .must_equal ["critical and value used in query must match"]
    end

    it "does not allow mismatching query and critical with >=" do
      validation_errors_from(monitor(critical: -> { 123.0 }, query: -> { "foo <= 12" }))
        .must_equal ["critical and value used in query must match"]
    end

    it "does not break on queries that are unparseable for critical" do
      validation_errors_from(monitor(critical: -> { 123.0 }, query: -> { "(last_5m) foo = 12" }))
        .must_equal []
    end

    it "sets no_data_timeframe to `nil` when notify_no_data is false" do
      monitor(
        notify_no_data: -> { false },
        no_data_timeframe: -> { 2 }
      ).build_json[:options][:no_data_timeframe].must_be_nil
    end

    it "can set notify_audit" do
      valid_monitor_json(notify_audit: -> { false }).dig(:options, :notify_audit).must_equal false
    end

    it "fails on deprecated metric alert type" do
      validation_error_from(monitor(type: -> { "metric alert" }))
        .must_include "query alert"
    end

    it "sets id when not given" do
      assert_json_equal(
        valid_monitor_json(id: -> { 123 }),
        expected_basic_json.merge(id: 123)
      )
    end

    it "strips query to avoid perma-diff" do
      valid_monitor_json(query: -> { " avg(last_5m) > 123.0 " })[:query].must_equal "avg(last_5m) > 123.0"
    end

    it "can set mention on the project" do
      valid_monitor_json(project: TestProject.new(mention: -> { "@slack-project" }))[:message].must_equal "@slack-project"
    end

    it "can set evaluation_delay" do
      valid_monitor_json(evaluation_delay: -> { 20 }).dig(:options, :evaluation_delay).must_equal 20
    end

    it "can set new_host_delay" do
      valid_monitor_json(new_host_delay: -> { 300 }).dig(:options, :new_host_delay).must_equal 300
    end

    it "can set new_group_delay" do
      valid_monitor_json(new_group_delay: -> { 120 }).dig(:options, :new_group_delay).must_equal 120
    end

    it "can set threshold_windows" do
      valid_monitor_json(threshold_windows: -> { 20 }).dig(:options, :threshold_windows).must_equal 20
    end

    it "can set scheduling_options" do
      valid_monitor_json(scheduling_options: -> { { evaluation_window: { day_starts: "14:00" } } }).dig(:options, :scheduling_options).must_equal({ evaluation_window: { day_starts: "14:00" } })
    end

    # happens when project/team have the same tags and they double up
    it "only sets tags once to avoid perma-diff when datadog unqiues them" do
      valid_monitor_json(tags: -> { ["a", "b", "a"] })[:tags].must_equal ["a", "b"]
    end

    it "does not allow invalid priority" do
      validation_errors_from(monitor(priority: -> { 2.0 }))
        .must_equal ["priority needs to be an Integer"]
    end

    it "does not include new_host_delay when new_group_delay is provided" do
      valid_monitor_json(new_host_delay: -> { 60 }, new_group_delay: -> { 20 })[:options].key?(:new_host_delay).must_equal(false)
    end

    it "blocks invalid service check query without .by early" do
      validation_errors_from(monitor(type: -> { "service check" }))
        .must_equal ["query must include a .by() at least .by(\"*\")"]
    end

    it "blocks names that create perma-diff" do
      validation_errors_from(monitor(name: -> { " oops" }))
        .must_equal ["name cannot start with a space"]
    end

    it "blocks invalid timeout_h" do
      validation_errors_from(monitor(timeout_h: -> { 200 }))
        .must_equal ["timeout_h must be <= 24"]
    end

    it "does not set no_data_timeframe for log alert to not break the UI" do
      json = monitor(
        type: -> { "log alert" },
        no_data_timeframe: -> { 10 }
      ).build_json
      refute json[:options].key?(:no_data_timeframe)
    end

    it "can set notification_preset_name" do
      monitor(notification_preset_name: -> { "hide_query" })
        .build_json.dig(:options, :notification_preset_name).must_equal "hide_query"
    end

    it "defaults to allowing no-data for log alerts" do
      monitor(type: -> { "log alert" })
        .build_json.dig(:options, :notify_no_data).must_equal false
    end

    it "can set group_retention_duration" do
      monitor(group_retention_duration: -> { "1h" })
        .build_json.dig(:options, :group_retention_duration).must_equal "1h"
    end

    describe "on_missing_data" do
      it "defaults" do
        monitor(
          type: -> { "event-v2 alert" }
        ).build_json.dig(:options, :on_missing_data).must_equal "default"
      end

      it "sets" do
        monitor(
          type: -> { "event-v2 alert" },
          on_missing_data: -> { "resolve" }
        ).build_json.dig(:options, :on_missing_data).must_equal "resolve"
      end
    end

    describe "renotify_interval" do
      it "sets 0 when disabled" do
        valid_monitor_json(renotify_interval: -> { false })[:options][:renotify_interval].must_equal 0
      end

      it "can set" do
        valid_monitor_json(renotify_interval: -> { 60 })[:options][:renotify_interval].must_equal 60
      end
    end

    describe "renotify_statuses" do
      it "sets alert and no-data when renotify_interval is set" do
        monitor(
          renotify_interval: -> { 10 }
        ).build_json[:options][:renotify_statuses].must_equal ["alert", "no data"]
      end

      it "sets warn when warning is defined" do
        monitor(
          renotify_interval: -> { 10 },
          warning: -> { 10 }
        ).build_json[:options][:renotify_statuses].must_equal ["alert", "no data", "warn"]
      end

      it "does not set no-data when no-data is disabled" do
        monitor(
          renotify_interval: -> { 10 },
          notify_no_data: -> { false }
        ).build_json[:options][:renotify_statuses].must_equal ["alert"]
      end

      it "do not set renotify_statuses when renotify_interval is 0" do
        monitor(
          renotify_interval: -> { 0 }
        ).build_json[:options][:renotify_statuses].must_be_nil
      end

      it "do not set renotify_statuses when renotify_interval is not defined" do
        monitor(
          renotify_interval: -> {}
        ).build_json[:options][:renotify_statuses].must_be_nil
      end
    end
  end

  describe "#validate_message_variables" do
    describe "with query alert style queries" do
      let(:mon) { monitor(query: -> { "avg(last_5m):avg:foo by {env} > 123.0" }) }

      it "passes without is_match" do
        validation_errors_from(mon).must_equal []
      end

      it "fails when using invalid is_match" do
        mon.stubs(:message).returns('{{#is_match "environment.name" "production"}}TEST{{/is_match}}')
        validation_errors_from(mon)
          .must_equal ["Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."]
      end

      it "fails when using invalid negative is_match" do
        mon.stubs(:message).returns('{{^is_match "environment.name" "production"}}TEST{{/is_match}}')
        validation_errors_from(mon)
          .must_equal ["Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."]
      end

      it "fails when using invalid is_exact_match" do
        mon.stubs(:message).returns('{{#is_exact_match "environment.name" "production"}}TEST{{/is_exact_match}}')
        validation_errors_from(mon)
          .must_equal ["Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."]
      end

      it "fails when not using .name" do
        mon.stubs(:message).returns('{{#is_match "env" "production"}}TEST{{/is_match}}')
        validation_errors_from(mon)
          .must_equal ["Used env in the message, but can only be used with env.name.\nGroup or filter the query by env to use it."]
      end

      it "ignores when not using quotes" do
        mon.stubs(:message).returns('{{#is_match env.name "production"}}TEST{{/is_match}}')
        validation_errors_from(mon).must_equal []
      end

      it "passes when using valid is_match" do
        mon.expects(:message).returns('{{#is_match "env.name" "production"}}TEST{{/is_match}}')
        validation_errors_from(mon).must_equal []
      end

      it "passes when using valid variable" do
        mon.expects(:message).returns("{{env.name}}")
        validation_errors_from(mon).must_equal []
      end

      it "passes when using variable from filter" do
        mon.stubs(:query).returns("avg(last_5m):avg:foo{bar:foo} by {env} > 123.0")
        mon.expects(:message).returns("{{bar.name}}")
        validation_errors_from(mon).must_equal []
      end

      it "passes when using unknown query" do
        mon.stubs(:query).returns("wuuut")
        mon.expects(:message).returns("{{bar.name}}")
        validation_errors_from(mon).must_equal []
      end

      it "does not show * from filter" do
        mon.stubs(:query).returns("avg(last_5m):avg:foo{*} by {env} > 123.0")
        mon.expects(:message).returns("{{bar.name}}")
        validation_errors_from(mon)
          .must_equal ["Used bar.name in the message, but can only be used with env.name.\nGroup or filter the query by bar to use it."]
      end

      it "fails when using invalid variable" do
        mon.expects(:message).returns("{{foo.name}}")
        validation_errors_from(mon)
          .must_equal ["Used foo.name in the message, but can only be used with env.name.\nGroup or filter the query by foo to use it."]
      end

      it "passes with [escaped] query style" do
        mon.stubs(:query).returns("avg(last_5m):avg:foo{bar.baz:foo} by {env} > 123.0")
        mon.expects(:message).returns("{{[bar.baz].name}}")
        validation_errors_from(mon).must_equal []
      end
    end

    describe "with service check style queries" do
      let(:mon) { monitor(query: -> { "\"foo\".over(\"bar\").by(\"env\")" }) }

      it "passes without is_match" do
        validation_errors_from(mon).must_equal []
      end

      it "fails when using invalid is_match" do
        mon.stubs(:message).returns('{{#is_match "environment.name" "production"}}TEST{{/is_match}}')
        validation_errors_from(mon)
          .must_equal ["Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."]
      end

      it "passes when using valid is_match" do
        mon.expects(:message).returns('{{#is_match "env.name" "production"}}TEST{{/is_match}}')
        validation_errors_from(mon).must_equal []
      end

      it "allows everything when using *" do
        mon.stubs(:message).returns('{{#is_match "environment.name" "production"}}TEST{{/is_match}}')
        mon.stubs(:query).returns("\"foo\".over(\"bar\").by(\"*\")")
        validation_errors_from(mon).must_equal []
      end
    end
  end

  describe "#validate_using_links" do
    it "fails when not using links in composite" do
      e = validation_error_from(monitor(query: "1 || 2", type: "composite"))
      e.must_include '["1", "2"]'
    end

    it "fails when not using links in slo alert" do
      e = validation_error_from(monitor(query: "error_budget(\"abcdef\")", type: "slo alert"))
      e.must_include 'instead of "abcdef"'
    end
  end

  describe "#validate_thresholds" do
    it "allows valid" do
      e = validation_errors_from(monitor(query: "a > 10", critical: 10, warning: 9))
      e.must_equal []
    end

    it "allows unknown" do
      e = validation_errors_from(monitor(query: "weird stuff", critical: 10, warning: 9))
      e.must_equal []
    end

    it "fails with invalid and >" do
      e = validation_errors_from(monitor(query: "a > 10", critical: 10, warning: 11))
      e.must_equal ["Warning threshold (11.0) must be less than the alert threshold (10.0) with > comparison"]
    end

    it "fails with invalid and <" do
      e = validation_errors_from(monitor(query: "a < 10", critical: 10, warning: 9))
      e.must_equal ["Warning threshold (9.0) must be greater than the alert threshold (10.0) with < comparison"]
    end
  end

  describe "#resolve_linked_tracking_ids" do
    let(:mon) do
      m = monitor(query: -> { "%{#{project.kennel_id}:mon}" })
      m.build
      m
    end

    it "does nothing for regular monitors" do
      mon.resolve_linked_tracking_ids!(id_map, force: false)
      mon.build_json[:query].must_equal "%{#{project.kennel_id}:mon}"
    end

    describe "composite monitor" do
      let(:mon) do
        monitor(type: -> { "composite" }, query: -> { "%{foo:mon_a} || !%{bar:mon_b}" })
      end

      it "fails when matching monitor is missing" do
        mon.build
        e = assert_raises Kennel::UnresolvableIdError do
          mon.resolve_linked_tracking_ids!(id_map, force: false)
        end
        e.message.must_include "test_project:m1 Unable to find monitor foo:mon_a"
      end

      it "does not fail when unable to try to resolve" do
        id_map.set("monitor", "foo:mon_a", Kennel::IdMap::NEW)
        id_map.set("monitor", "bar:mon_b", Kennel::IdMap::NEW)
        mon.build
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal "%{foo:mon_a} || !%{bar:mon_b}", "query not modified"
      end

      it "resolves correctly with a matching monitor" do
        id_map.set("monitor", "foo:mon_x", 3)
        id_map.set("monitor", "foo:mon_a", 1)
        id_map.set("monitor", "bar:mon_b", 2)
        mon.build
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal("1 || !2")
      end
    end

    describe "slo alert monitor" do
      let(:mon) do
        monitor(type: -> { "slo alert" }, query: -> { "error_budget(\"%{foo:slo_a}\").over(\"7d\") > #{critical}" })
      end

      it "fails when matching monitor is missing" do
        mon.build
        e = assert_raises Kennel::UnresolvableIdError do
          mon.resolve_linked_tracking_ids!(id_map, force: false)
        end
        e.message.must_include "test_project:m1 Unable to find slo foo:slo_a"
      end

      it "resolves correctly with a matching monitor" do
        id_map.set("slo", "foo:slo_x", "3")
        id_map.set("slo", "foo:slo_a", "1")
        id_map.set("slo", "foo:slo_b", "2")
        mon.build
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal("error_budget(\"1\").over(\"7d\") > 123.0")
      end
    end
  end

  describe "#diff" do
    # minitest defines diff, do not override it
    def diff_resource(e, a)
      a = expected_basic_json.merge(a)
      a[:options] = expected_basic_json[:options].merge(a[:options] || {})
      m = monitor(e)
      m.build
      m.diff(a)
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

    it "ignores missing include_tags and require_full_window for service alerts" do
      expected_basic_json[:query] = "foo.by(x)"
      expected_basic_json[:options].delete(:include_tags)
      expected_basic_json[:options].delete(:require_full_window)
      expected_basic_json[:options][:thresholds][:critical] = 123
      diff_resource(
        {
          type: -> { "service check" },
          query: -> { "foo.by(x)" },
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
      diff_resource(
        {
          type: -> { "event alert" },
          critical: -> { 0 },
          notify_no_data: -> { true }
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

  describe "#allowed_update_error" do
    it "allows update of name" do
      monitor.allowed_update_error(name: "foo", type: monitor.type).must_be_nil
    end

    it "disallows update of type" do
      monitor.allowed_update_error(type: "x").must_equal "cannot update type from x to query alert"
    end

    it "allows update of metric to query which is used by the importer" do
      monitor.allowed_update_error(type: "metric alert").must_be_nil
    end
  end

  describe ".url" do
    it "shows full url" do
      Kennel::Models::Monitor.url(111).must_equal "https://app.datadoghq.com/monitors/111/edit"
    end
  end

  describe ".api_resource" do
    it "is set" do
      Kennel::Models::Monitor.api_resource.must_equal "monitor"
    end
  end

  describe ".parse_url" do
    it "parses" do
      url = "https://app.datadoghq.com/monitors/123"
      Kennel::Models::Monitor.parse_url(url).must_equal 123
    end

    it "parses with # which datadog links to in the UI" do
      url = "https://app.datadoghq.com/monitors#123"
      Kennel::Models::Monitor.parse_url(url).must_equal 123
    end

    it "parses SLO alert URLs" do
      url = "https://app.datadoghq.com/slo/edit/123abc456def123/alerts/789"
      Kennel::Models::Monitor.parse_url(url).must_equal 789
    end

    it "fails to parse other" do
      url = "https://app.datadoghq.com/dashboard/bet-foo-bar?from_ts=1585064592575&to_ts=1585068192575&live=true"
      Kennel::Models::Monitor.parse_url(url).must_be_nil
    end
  end

  describe ".normalize" do
    it "works with empty" do
      Kennel::Models::Monitor.normalize({}, options: {})
    end

    it "does not ignore notify_no_data false since default is true and that would make import incorrect" do
      actual = { options: { notify_no_data: false } }
      expected = { options: { notify_no_data: false } }
      Kennel::Models::Monitor.normalize(expected, actual)
      expected.must_equal(options: { notify_no_data: false })
      actual.must_equal(options: { notify_no_data: false })
    end

    it "ignores defaults" do
      actual = { options: { timeout_h: 0 } }
      expected = { options: { timeout_h: 0 } }
      Kennel::Models::Monitor.normalize(expected, actual)
      expected.must_equal(options: {})
      actual.must_equal(options: {})
    end
  end
end
