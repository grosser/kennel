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
      tags: ["service:test_project", "team:test_team"],
      priority: nil,
      options: {
        timeout_h: 0,
        notify_no_data: true,
        no_data_timeframe: 60,
        notify_audit: false,
        require_full_window: true,
        new_host_delay: 300,
        include_tags: true,
        escalation_message: nil,
        evaluation_delay: nil,
        locked: false,
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

    it "can set require_full_window" do
      monitor(require_full_window: -> { true }).as_json[:options][:require_full_window].must_equal true
    end

    it "can set variables" do
      monitor(variables: -> { { a: 1 } }).as_json[:options][:variables].must_equal a: 1
    end

    describe "query alert" do
      it "converts threshold values to floats to avoid api diff" do
        monitor(critical: -> { 234 }).as_json
          .dig(:options, :thresholds, :critical).must_equal 234.0
      end

      it "does not converts threshold values to floats for types that store integers" do
        monitor(critical: -> { 234 }, type: -> { "service check" }, query: -> { "foo.by(x)" }).as_json
          .dig(:options, :thresholds, :critical).must_equal 234
      end
    end

    it "does not set thresholds for composite monitors" do
      json = monitor(
        critical: -> { raise },
        query: -> { "1 || 2" },
        type: -> { "composite" },
        validate_using_links: ->(*) {}
      ).as_json
      refute json[:options].key?(:thresholds)
    end

    it "fills default values for service check ok/warning" do
      json = monitor(critical: -> { 234 }, type: -> { "service check" }, query: -> { "foo.by(x)" }).as_json
      json.dig(:options, :thresholds, :ok).must_equal 1
      json.dig(:options, :thresholds, :warning).must_equal 1
    end

    it "allows next_x interval for query alert type" do
      monitor(critical: -> { 234.1 }, query: -> { "avg(next_20m).count() < #{critical}" }).as_json
    end

    it "does not allow mismatching query and critical" do
      validation_error_from(monitor(critical: -> { 123.0 }, query: -> { "foo < 12" }))
        .must_equal "critical and value used in query must match"
    end

    it "does not allow mismatching query and critical with >=" do
      validation_error_from(monitor(critical: -> { 123.0 }, query: -> { "foo <= 12" }))
        .must_equal "critical and value used in query must match"
    end

    it "does not break on queries that are unparseable for critical" do
      validation_errors_from(monitor(critical: -> { 123.0 }, query: -> { "(last_5m) foo = 12" }))
        .must_be_empty
    end

    it "sets no_data_timeframe to `nil` when notify_no_data is false" do
      monitor(
        notify_no_data: -> { false },
        no_data_timeframe: -> { 2 }
      ).as_json[:options][:no_data_timeframe].must_be_nil
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
      validation_error_from(monitor(type: -> { "metric alert" }))
        .must_include "query alert"
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

    it "can set mention on the project" do
      monitor(project: TestProject.new(mention: -> { "@slack-project" })).as_json[:message].must_equal "@slack-project"
    end

    it "can set evaluation_delay" do
      monitor(evaluation_delay: -> { 20 }).as_json.dig(:options, :evaluation_delay).must_equal 20
    end

    it "can set new_host_delay" do
      monitor(new_host_delay: -> { 300 }).as_json.dig(:options, :new_host_delay).must_equal 300
    end

    it "can set new_group_delay" do
      monitor(new_group_delay: -> { 120 }).as_json.dig(:options, :new_group_delay).must_equal 120
    end

    it "can set threshold_windows" do
      monitor(threshold_windows: -> { 20 }).as_json.dig(:options, :threshold_windows).must_equal 20
    end

    it "can set scheduling_options" do
      monitor(scheduling_options: -> { { evaluation_window: { day_starts: "14:00" } } }).as_json.dig(:options, :scheduling_options).must_equal({ evaluation_window: { day_starts: "14:00" } })
    end

    # happens when project/team have the same tags and they double up
    it "only sets tags once to avoid perma-diff when datadog unqiues them" do
      monitor(tags: -> { ["a", "b", "a"] }).as_json[:tags].must_equal ["a", "b"]
    end

    it "does not allow invalid priority" do
      validation_error_from(monitor(priority: -> { 2.0 }))
        .must_equal "priority needs to be an Integer"
    end

    it "does not include new_host_delay when new_group_delay is provided" do
      monitor(new_host_delay: -> { 60 }, new_group_delay: -> { 20 }).as_json.dig(:options).key?(:new_host_delay).must_equal(false)
    end

    it "blocks invalid service check query without .by early" do
      validation_error_from(monitor(type: -> { "service check" }))
        .must_equal "query must include a .by() at least .by(\"*\")"
    end

    it "blocks names that create perma-diff" do
      validation_error_from(monitor(name: -> { " oops" }))
        .must_equal "name cannot start with a space"
    end

    it "blocks invalid timeout_h" do
      validation_error_from(monitor(timeout_h: -> { 200 }))
        .must_equal "timeout_h must be <= 24"
    end

    it "does not set no_data_timeframe for log alert to not break the UI" do
      json = monitor(
        type: -> { "log alert" },
        no_data_timeframe: -> { 10 }
      ).as_json
      refute json[:options].key?(:no_data_timeframe)
    end

    describe "on_missing_data" do
      it "defaults" do
        monitor(
          type: -> { "event-v2 alert" }
        ).as_json.dig(:options, :on_missing_data).must_equal "default"
      end

      it "sets" do
        monitor(
          type: -> { "event-v2 alert" },
          on_missing_data: -> { "resolve" }
        ).as_json.dig(:options, :on_missing_data).must_equal "resolve"
      end
    end

    describe "renotify_interval" do
      it "sets 0 when disabled" do
        monitor(renotify_interval: -> { false }).as_json[:options][:renotify_interval].must_equal 0
      end

      it "can set" do
        monitor(renotify_interval: -> { 60 }).as_json[:options][:renotify_interval].must_equal 60
      end

      it "fails on invalid" do
        validation_error_from(monitor(renotify_interval: -> { 123 }))
          .must_include "renotify_interval must be one of 0, 10, 20,"
      end
    end

    describe "renotify_statuses" do
      it "sets alert and no-data when renotify_interval is set" do
        monitor(
          renotify_interval: -> { 10 }
        ).as_json[:options][:renotify_statuses].must_equal ["alert", "no data"]
      end

      it "sets warn when warning is defined" do
        monitor(
          renotify_interval: -> { 10 },
          warning: -> { 10 }
        ).as_json[:options][:renotify_statuses].must_equal ["alert", "no data", "warn"]
      end

      it "does not set no-data when no-data is disabled" do
        monitor(
          renotify_interval: -> { 10 },
          notify_no_data: -> { false }
        ).as_json[:options][:renotify_statuses].must_equal ["alert"]
      end

      it "do not set renotify_statuses when renotify_interval is 0" do
        monitor(
          renotify_interval: -> { 0 }
        ).as_json[:options][:renotify_statuses].must_be_nil
      end

      it "do not set renotify_statuses when renotify_interval is not defined" do
        monitor(
          renotify_interval: -> {}
        ).as_json[:options][:renotify_statuses].must_be_nil
      end
    end
  end

  describe "#validate_message_variables" do
    describe "with query alert style queries" do
      let(:mon) { monitor(query: -> { "avg(last_5m):avg:foo by {env} > 123.0" }) }

      it "passes without is_match" do
        mon.as_json
      end

      it "fails when using invalid is_match" do
        mon.stubs(:message).returns('{{#is_match "environment.name" "production"}}TEST{{/is_match}}')
        validation_error_from(mon)
          .must_equal "Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."
      end

      it "fails when using invalid negative is_match" do
        mon.stubs(:message).returns('{{^is_match "environment.name" "production"}}TEST{{/is_match}}')
        validation_error_from(mon)
          .must_equal "Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."
      end

      it "fails when using invalid is_exact_match" do
        mon.stubs(:message).returns('{{#is_exact_match "environment.name" "production"}}TEST{{/is_exact_match}}')
        validation_error_from(mon)
          .must_equal "Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."
      end

      it "fails when not using .name" do
        mon.stubs(:message).returns('{{#is_match "env" "production"}}TEST{{/is_match}}')
        validation_error_from(mon)
          .must_equal "Used env in the message, but can only be used with env.name.\nGroup or filter the query by env to use it."
      end

      it "ignores when not using quotes" do
        mon.stubs(:message).returns('{{#is_match env.name "production"}}TEST{{/is_match}}')
        mon.as_json
      end

      it "passes when using valid is_match" do
        mon.expects(:message).returns('{{#is_match "env.name" "production"}}TEST{{/is_match}}')
        mon.as_json
      end

      it "passes when using valid variable" do
        mon.expects(:message).returns("{{env.name}}")
        mon.as_json
      end

      it "passes when using variable from filter" do
        mon.stubs(:query).returns("avg(last_5m):avg:foo{bar:foo} by {env} > 123.0")
        mon.expects(:message).returns("{{bar.name}}")
        mon.as_json
      end

      it "passes when using unknown query" do
        mon.stubs(:query).returns("wuuut")
        mon.expects(:message).returns("{{bar.name}}")
        mon.as_json
      end

      it "does not show * from filter" do
        mon.stubs(:query).returns("avg(last_5m):avg:foo{*} by {env} > 123.0")
        mon.expects(:message).returns("{{bar.name}}")
        validation_error_from(mon)
          .must_equal "Used bar.name in the message, but can only be used with env.name.\nGroup or filter the query by bar to use it."
      end

      it "fails when using invalid variable" do
        mon.expects(:message).returns("{{foo.name}}")
        validation_error_from(mon)
          .must_equal "Used foo.name in the message, but can only be used with env.name.\nGroup or filter the query by foo to use it."
      end

      it "passes with [escaped] query style" do
        mon.stubs(:query).returns("avg(last_5m):avg:foo{bar.baz:foo} by {env} > 123.0")
        mon.expects(:message).returns("{{[bar.baz].name}}")
        mon.as_json
      end
    end

    describe "with service check style queries" do
      let(:mon) { monitor(query: -> { "\"foo\".over(\"bar\").by(\"env\")" }) }

      it "passes without is_match" do
        mon.as_json
      end

      it "fails when using invalid is_match" do
        mon.stubs(:message).returns('{{#is_match "environment.name" "production"}}TEST{{/is_match}}')
        validation_error_from(mon)
          .must_equal "Used environment.name in the message, but can only be used with env.name.\nGroup or filter the query by environment to use it."
      end

      it "passes when using valid is_match" do
        mon.expects(:message).returns('{{#is_match "env.name" "production"}}TEST{{/is_match}}')
        mon.as_json
      end

      it "allows everything when using *" do
        mon.stubs(:message).returns('{{#is_match "environment.name" "production"}}TEST{{/is_match}}')
        mon.stubs(:query).returns("\"foo\".over(\"bar\").by(\"*\")")
        mon.as_json
      end
    end
  end

  describe "#validate_using_links" do
    def make_invalid
      monitor(
        critical: -> { raise },
        query: -> { "1 || 2" },
        type: -> { "composite" }
      )
    end

    def with_allow_list(items)
      const = Kennel::Models::Monitor::ALLOWED_UNLINKED
      begin
        const.concat items
        yield
      ensure
        const.pop(items.size)
      end
    end

    it "fails when not using links" do
      validation_error_from(make_invalid)
        .must_include '["1", "2"]'
    end

    it "allows external list" do
      with_allow_list [["test_project:m1", "1"], ["test_project:m1", "2"]] do
        validation_errors_from(make_invalid)
          .must_be_empty
      end
    end
  end

  describe "#resolve_linked_tracking_ids" do
    let(:mon) do
      monitor(query: -> { "%{#{project.kennel_id}:mon}" })
    end

    it "does nothing for regular monitors" do
      mon.resolve_linked_tracking_ids!(id_map, force: false)
      mon.as_json[:query].must_equal "%{#{project.kennel_id}:mon}"
    end

    describe "composite monitor" do
      let(:mon) do
        monitor(type: -> { "composite" }, query: -> { "%{foo:mon_a} || !%{bar:mon_b}" })
      end

      it "fails when matching monitor is missing" do
        e = assert_raises Kennel::UnresolvableIdError do
          mon.resolve_linked_tracking_ids!(id_map, force: false)
        end
        e.message.must_include "test_project:m1 Unable to find monitor foo:mon_a"
      end

      it "does not fail when unable to try to resolve" do
        id_map.set("monitor", "foo:mon_a", Kennel::IdMap::NEW)
        id_map.set("monitor", "bar:mon_b", Kennel::IdMap::NEW)
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal "%{foo:mon_a} || !%{bar:mon_b}", "query not modified"
      end

      it "resolves correctly with a matching monitor" do
        id_map.set("monitor", "foo:mon_x", 3)
        id_map.set("monitor", "foo:mon_a", 1)
        id_map.set("monitor", "bar:mon_b", 2)
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal("1 || !2")
      end
    end

    describe "slo alert monitor" do
      let(:mon) do
        monitor(type: -> { "slo alert" }, query: -> { "error_budget(\"%{foo:slo_a}\").over(\"7d\") > #{critical}" })
      end

      it "fails when matching monitor is missing" do
        e = assert_raises Kennel::UnresolvableIdError do
          mon.resolve_linked_tracking_ids!(id_map, force: false)
        end
        e.message.must_include "test_project:m1 Unable to find slo foo:slo_a"
      end

      it "resolves correctly with a matching monitor" do
        id_map.set("slo", "foo:slo_x", "3")
        id_map.set("slo", "foo:slo_a", "1")
        id_map.set("slo", "foo:slo_b", "2")
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

  describe "#validate_update!" do
    it "allows update of name" do
      monitor.validate_update!([["~", "name", "foo", "bar"]])
    end

    it "disallows update of type" do
      e = assert_raises Kennel::DisallowedUpdateError do
        monitor.validate_update!([["~", "type", "foo", "bar"]])
      end
      e.message.must_match(/datadog.*allow.*type/i)
    end

    it "allows update of metric to query which is used by the importer" do
      monitor.validate_update!([["~", "type", "metric alert", "query alert"]])
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
