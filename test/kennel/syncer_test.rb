# frozen_string_literal: true
require_relative "../test_helper"
require "stringio"

SingleCov.covered!
SingleCov.covered! file: "lib/kennel/syncer/plan_displayer.rb"
SingleCov.covered! file: "lib/kennel/syncer/resolver.rb"
SingleCov.covered! file: "lib/kennel/syncer/types.rb"

describe Kennel::Syncer do
  define_test_classes

  def project(pid)
    project = TestProject.new
    project.define_singleton_method(:kennel_id) { pid }
    project
  end

  def tagged(api_resource, hash)
    Kennel::Api.tag(api_resource, hash)
  end

  def monitor_api_response(pid, cid, extra = {})
    tagged("monitor", {
      id: 1,
      tags: extra.delete(:tags) || ["team:test-team"],
      message: "@slack-foo\n-- Managed by kennel #{pid}:#{cid} in test/test_helper.rb, do not modify manually",
      options: {}
    }.merge(extra))
  end

  def slo_api_response(pid, cid, extra = {})
    tagged("slo", {
      id: "1",
      description: "x\n-- Managed by kennel #{pid}:#{cid} in test/test_helper.rb, do not modify manually",
      tags: []
    }.merge(extra))
  end

  def monitor(pid, cid, extra = {})
    monitor = Kennel::Models::Monitor.new(
      project(pid),
      query: -> { "avg(last_5m) > #{critical}" },
      kennel_id: -> { cid },
      type: -> { "query alert" },
      critical: -> { 1.0 },
      id: -> { extra[:id] }
    )
    monitor.build

    # make the diff simple
    monitor.as_json[:options] = {
      escalation_message: nil,
      evaluation_delay: nil
    }
    monitor.as_json.delete_if { |k, _| ![:tags, :message, :options].include?(k) }
    monitor.as_json.merge!(extra)

    monitor
  end

  def synthetic(pid, cid, extra = {})
    synthetic = Kennel::Models::SyntheticTest.new(
      project(pid),
      kennel_id: -> { cid },
      id: -> { extra[:id] },
      locations: -> { ["aws:us-west-1"] },
      tags: -> { [] },
      config: -> { nil },
      message: -> { nil },
      subtype: -> { nil },
      type: -> { nil },
      name: -> { nil },
      options: -> { nil }
    )

    synthetic.build
    synthetic.as_json.delete_if { |k, _| ![:tags, :message].include?(k) }
    synthetic.as_json.merge!(extra)

    synthetic
  end

  def dashboard(pid, cid, extra = {})
    dash = Kennel::Models::Dashboard.new(
      project(pid),
      title: -> { "x" },
      description: -> { "x" },
      layout_type: -> { "ordered" },
      kennel_id: -> { cid },
      id: -> { extra[:id]&.to_s }
    )
    dash.build
    dash.as_json.delete_if { |k, _| ![:description, :options, :widgets, :template_variables].include?(k) }
    dash.as_json.merge!(extra)
    dash
  end

  def slo(pid, cid, extra = {})
    slo = Kennel::Models::Slo.new(
      project(pid),
      name: -> { "x" },
      description: -> { "x" },
      type: -> { "metric" },
      kennel_id: -> { cid },
      id: -> { extra[:id]&.to_s },
      thresholds: -> { [] }
    )
    slo.build
    slo.as_json.merge!(extra)
    slo
  end

  def add_identical
    expected << monitor("a", "b")
    monitors << monitor_api_response("a", "b")
  end

  def change(*args)
    Kennel::Syncer::Change.new(*args)
  end

  let(:api) { stub("Api") }
  let(:monitors) { [] }
  let(:dashboards) { [] }
  let(:slos) { [] }
  let(:synthetics) { [] }
  let(:expected) { [] }
  let(:actual) { dashboards + monitors + slos + synthetics }
  let(:strict_imports) { [true] } # array to allow modification
  let(:project_filter) { [] }
  let(:tracking_id_filter) { [] }
  let(:filter) do
    p_arg = Kennel::Utils.presence(project_filter)&.join(",")
    t_arg = Kennel::Utils.presence(tracking_id_filter)&.join(",")
    with_env(PROJECT: p_arg, TRACKING_ID: t_arg) { Kennel::Filter.new }
  end
  let(:syncer) do
    actual.each do |a|
      klass = a.fetch(:klass)
      raise "Bad test data: #{a.inspect}" unless a.fetch(:tracking_id) == klass.parse_tracking_id(a)
    end

    Kennel::Syncer.new(
      api, expected, actual,
      filter: filter,
      strict_imports: strict_imports[0]
    )
  end

  before do
    Kennel::Progress.stubs(:print).yields
    api.stubs(:fill_details!)
  end

  capture_all # TODO: pass an IO to syncer so we don't have to capture all output

  describe "planning" do # plan + print_plan
    let(:plan) do
      (monitors + dashboards).each { |m| m[:id] ||= 123 } # existing components always have an id
      syncer.print_plan
      syncer.plan
    end
    let(:output) do
      plan
      stdout.string.gsub(/\e\[\d+m(.*)\e\[0m/, "\\1") # remove colors
    end

    it "does nothing when everything is empty" do
      plan.changes.must_be_empty
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "creates missing" do
      expected << monitor("a", "b")
      plan.changes.must_equal [change(:create, "monitor", "a:b", nil)]
      output.must_equal "Plan:\nCreate monitor a:b\n"
    end

    it "returns a plan" do
      expected << monitor("a", "b")
      plan.changes.must_equal [change(:create, "monitor", "a:b", nil)]
    end

    it "ignores identical" do
      add_identical
      plan.changes.must_be_empty
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "ignores readonly attributes since we do not generate them" do
      expected << monitor("a", "b")
      monitors << monitor_api_response("a", "b", created: true)
      plan.changes.must_be_empty
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "ignores silencing since that is managed via the UI" do
      expected << monitor("a", "b")
      monitors << monitor_api_response("a", "b", options: { silenced: { "*" => 1 } })
      plan.changes.must_be_empty
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "updates when changed" do
      expected << monitor("a", "b", foo: "bar", bar: "foo", nested: { foo: "bar" })
      monitors << monitor_api_response("a", "b", foo: "baz", baz: "foo", nested: { foo: "baz" })
      plan.changes.must_equal [change(:update, "monitor", "a:b", 1)]
      output.must_equal <<~TEXT
        Plan:
        Update monitor a:b
          -baz \"foo\" -> nil
          ~foo \"baz\" -> \"bar\"
          ~nested.foo \"baz\" -> \"bar\"
          +bar nil -> \"foo\"
      TEXT
    end

    it "shows long updates nicely" do
      expected << monitor("a", "b", foo: "something very long but not too long I do not know")
      monitors << monitor_api_response("a", "b", foo: "something shorter but still very long but also different")
      output.must_equal <<~TEXT
        Plan:
        Update monitor a:b
          ~foo
            \"something shorter but still very long but also different\" ->
            \"something very long but not too long I do not know\"
      TEXT
    end

    it "shows added tags nicely" do
      expected << monitor("a", "b", tags: ["foo", "bar"])
      monitors << monitor_api_response("a", "b", tags: ["foo", "baz"])
      output.must_equal <<~TEXT
        Plan:
        Update monitor a:b
          ~tags[1] \"baz\" -> \"bar\"
      TEXT
    end

    it "deletes when removed from code" do
      monitors << monitor_api_response("a", "b", id: 1)
      plan.changes.must_equal [change(:delete, "monitor", "a:b", 1)]
      output.must_equal "Plan:\nDelete monitor a:b\n"
    end

    it "deletes in logical order" do
      monitors << monitor_api_response("a", "a")
      dashboards << tagged("dashboard", {
        id: "abc",
        description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually"
      })
      slos << slo_api_response("a", "c")
      output.must_equal "Plan:\nDelete dashboard a:b\nDelete slo a:c\nDelete monitor a:a\n"
    end

    it "deletes newest when existing monitor was copied" do
      expected << monitor("a", "b")
      monitors << monitor_api_response("a", "b")
      monitors << monitor_api_response("a", "b", tags: ["old"])
      output.must_equal "Plan:\nDelete monitor a:b\n"
    end

    it "does not break on nil tracking field (dashboards can have nil description)" do
      monitors << monitor_api_response("a", "b", message: nil, tracking_id: nil)
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "leaves unmanaged alone" do
      monitors << monitor_api_response("ignore", "ignore", message: "foo", tags: [])
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "shows progress" do
      Kennel::Progress.unstub(:print)
      output.must_equal "Plan:\nNothing to do\n"
      stderr.string.gsub(/\.\.\. .*?\d\.\d+s/, "... 0.0s").must_equal <<~OUTPUT
        Diffing ...
        Diffing ... 0.0s
      OUTPUT
    end

    it "fails when user copy-pasted existing message with kennel id since that would lead to bad updates" do
      expected << monitor("a", "b", id: 234, foo: "bar", message: "foo\n-- Managed by kennel foo:bar in foo.rb")
      monitors << monitor_api_response("a", "b", id: 234)
      assert_raises(RuntimeError) { output }.message.must_equal(
        "a:b Remove \"-- Managed by kennel\" line from message to copy a resource"
      )
    end

    describe "with project filter" do
      let(:project_filter) { ["a"] }

      it "finds diff when filtered is added" do
        expected << monitor("a", "c")
        output.must_equal "Plan:\nCreate monitor a:c\n"
      end

      it "ignores not found projects" do
        project_filter.unshift "b"
        expected << monitor("a", "c")
        output.must_equal "Plan:\nCreate monitor a:c\n"
      end

      it "leaves unmanaged alone" do
        add_identical
        monitors << monitor_api_response("ignore", "ignore", id: 123, message: "foo", tags: [])
        output.must_equal "Plan:\nNothing to do\n"
      end

      it "updates without tracking when previously unmanaged" do
        expected << monitor("a", "b", id: 1)
        monitors << monitor_api_response("a", "", message: "old stuff")
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message \"old stuff\" -> \"@slack-foo\"
        TEXT
      end

      it "updates when using multiple tracking ids" do
        project_filter.unshift "b"
        expected << monitor("a", "b", id: 1)
        monitors << monitor_api_response("a", "", id: 1, message: "old stuff")
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message \"old stuff\" -> \"@slack-foo\"
        TEXT
      end

      it "can plan when linked only by id during update" do
        expected << monitor("a", "b", id: 123, message: "")
        monitors << monitor_api_response("a", "b", id: 123, message: "")
        output.must_equal "Plan:\nNothing to do\n"
      end

      it "can resolve by tracking id outside of the filter" do
        monitors << monitor_api_response("xxx", "x", id: 123)
        expected << slo("a", "b", monitor_ids: ["xxx:x"])
        output.must_equal <<~OUTPUT
          Plan:
          Create slo a:b
        OUTPUT
      end
    end

    describe "with tracing_id filter" do
      let(:project_filter) { tracking_id_filter.map { |id| id.split(":").first } }
      let(:tracking_id_filter) { ["a:c"] }

      it "finds diff when filtered is added" do
        expected << monitor("a", "c")
        output.must_equal "Plan:\nCreate monitor a:c\n"
      end

      it "ignores diff when other is removed" do
        monitors << monitor_api_response("a", "b")
        output.must_equal "Plan:\nNothing to do\n"
      end
    end

    describe "dashboards" do
      it "can plan for dashboards" do
        expected << dashboard("a", "b", id: "abc")
        dashboards << tagged("dashboard", {
          id: "abc",
          template_variables: [],
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified_at: "2015-12-17T23:12:26.726234+00:00"
        })
        api.expects(:fill_details!).with { dashboards.last[:widgets] = [] }
        output.must_equal "Plan:\nNothing to do\n"
      end
    end

    describe "slos" do
      before do
        expected << slo("a", "b", id: "abc")
        slos << slo_api_response(
          "a", "b",
          id: "abc",
          name: "x\u{1F512}",
          type: "metric",
          thresholds: [],
          tags: ["team:test-team"]
        )
      end

      it "can plan for slos" do
        output.must_equal "Plan:\nNothing to do\n"
      end

      it "updates slos before their monitors" do
        slos[-1][:tags] << "foo"
        expected << monitor("a", "c")
        monitors << monitor_api_response("a", "c", tags: ["foo"])
        output.scan(/Update \S+/).must_equal ["Update slo", "Update monitor"]
      end
    end

    describe "replacement" do
      before do
        expected << monitor("a", "b", id: 234, foo: "bar")
        monitors << monitor_api_response("a", "b", id: 234)
      end

      it "updates via replace" do
        monitors.last[:message] = "nope" # actual is not marked yet
        monitors.last[:tracking_id] = nil # actual is not marked yet
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message
              - nope
              + @slack-foo
              + -- Managed by kennel a:b in test/test_helper.rb, do not modify manually
            +foo nil -> \"bar\"
        TEXT
      end

      it "can update renamed components" do
        monitors.last[:message] = "foo\n-- Managed by kennel foo:bar in foo.rb"
        monitors.last[:tracking_id] = "foo:bar"
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message
              - foo
              + @slack-foo
              - -- Managed by kennel foo:bar in foo.rb
              + -- Managed by kennel a:b in test/test_helper.rb, do not modify manually
            +foo nil -> \"bar\"
        TEXT
      end

      it "can update renamed components without other diff" do
        expected.last.as_json.delete(:foo)
        monitors.last[:message] = "foo\n-- Managed by kennel foo:bar in foo.rb"
        monitors.last[:tracking_id] = "foo:bar"
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message
              - foo
              + @slack-foo
              - -- Managed by kennel foo:bar in foo.rb
              + -- Managed by kennel a:b in test/test_helper.rb, do not modify manually
        TEXT
      end

      describe "when expected id was not found" do
        before { monitors.pop }

        it "warns without strict_imports" do
          strict_imports.replace [false]
          output.must_equal <<~TXT
            Warning: monitor a:b specifies id 234, but no such monitor exists. 'id' will be ignored. Remove the `id: -> { 234 }` line.
            Plan:
            Create monitor a:b
          TXT
        end

        it "raises with strict_imports" do
          e = assert_raises(RuntimeError) { output }
          e.message.must_equal "Unable to find existing monitor with id 234\nIf the monitor was deleted, remove the `id: -> { 234 }` line."
        end
      end
    end
  end

  describe "#confirm" do
    def expect_gets(answer)
      Kennel.in.unstub(:gets)
      Kennel.in.stubs(:gets).returns(answer)
    end

    before do
      expected << monitor("a", "b")
      Kennel.in.stubs(:tty?).returns(true)
      Kennel.err.stubs(:tty?).returns(true)
      Kennel.in.expects(:gets).with { raise "unexpected Kennel.in.gets called" }.never
    end

    it "confirms on y" do
      expect_gets("y\n")
      assert syncer.confirm
      stderr.string.must_include "\e[31mExecute Plan ? -  press 'y' to continue: \e[0m"
    end

    it "confirms when automated" do
      Kennel.in.stubs(:tty?).returns(false)
      assert syncer.confirm
    end

    it "confirms when on CI" do
      with_env CI: "true" do
        assert syncer.confirm
      end
    end

    it "denies on n" do
      expect_gets("n\n")
      refute syncer.confirm
    end

    it "denies when nothing changed" do
      expected.clear
      refute syncer.confirm
      stdout.string.must_equal ""
    end
  end

  describe "#update" do
    let(:update) do
      syncer.update
    end

    let(:output) do
      update
      stdout.string
    end

    it "does nothing when nothing is to do" do
      output.must_equal ""
    end

    it "creates" do
      expected << monitor("a", "b")
      api.expects(:create).with("monitor", expected.first.as_json).returns(tagged("monitor", expected.first.as_json.merge(id: 123)))
      output.must_equal <<~TXT
        Creating monitor a:b
        \e[1A\033[KCreated monitor a:b https://app.datadoghq.com/monitors/123/edit
      TXT
    end

    it "returns a changelog" do
      expected << monitor("a", "b")
      api.expects(:create).with("monitor", expected.first.as_json).returns(tagged("monitor", expected.first.as_json.merge(id: 123)))
      syncer.update.changes.must_equal [change(:create, "monitor", "a:b", 123)]
    end

    it "sets values we do not compare on" do
      expected << monitor("a", "b", type: "event alert", options: { thresholds: { critical: 2 } })
      sent = deep_dup(expected.first.as_json)
      sent[:message] = "@slack-foo\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually".lstrip
      api.expects(:create).with("monitor", sent).returns(tagged("monitor", sent.merge(id: 123)))
      output.must_equal <<~TXT
        Creating monitor a:b
        \e[1A\033[KCreated monitor a:b https://app.datadoghq.com/monitors/123/edit
      TXT
    end

    it "updates" do
      expected << monitor("a", "b", foo: "bar")
      monitors << monitor_api_response("a", "b", id: 123)
      api.expects(:update).with("monitor", 123, expected.first.as_json).returns(tagged("monitor", expected.first.as_json.merge(id: 123)))
      update.changes.must_equal [change(:update, "monitor", "a:b", 123)]
      output.must_equal <<~TXT
        Updating monitor a:b https://app.datadoghq.com/monitors/123/edit
        \e[1A\033[KUpdated monitor a:b https://app.datadoghq.com/monitors/123/edit
      TXT
    end

    it "deletes" do
      monitors << monitor_api_response("a", "b", id: 123)
      api.expects(:delete).with("monitor", 123).returns({})
      update.changes.must_equal [change(:delete, "monitor", "a:b", 123)]
      output.must_equal <<~TXT
        Deleting monitor a:b 123
        \e[1A\033[KDeleted monitor a:b 123
      TXT
    end

    it "can create multiple dependent resources" do
      monitor = monitor("a", "b")
      slo = slo("a", "c", monitor_ids: ["a:b"])
      expected << slo
      expected << monitor

      # Slightly misleading, since monitor.as_json remains the same object (which
      # is good enough for api.expects.with), but its contents are mutated by
      # the syncer.
      api.expects(:create)
        .with("monitor", monitor.as_json)
        .returns(tagged("monitor", monitor.as_json.merge(id: 1, message: "\n-- Managed by kennel a:b")))

      api.expects(:create)
        .with(
          "slo",
          slo.as_json.merge(
            monitor_ids: [1],
            description: "x\n-- Managed by kennel a:c in test/test_helper.rb, do not modify manually"
          )
        ).returns(tagged("monitor", id: 2))
      output.must_equal <<~TXT
        Creating monitor a:b
        \e[1A\033[KCreated monitor a:b https://app.datadoghq.com/monitors/1/edit
        Creating slo a:c
        \e[1A\033[KCreated slo a:c https://app.datadoghq.com/slo?slo_id=2
      TXT
    end

    it "fails on circular dependencies" do
      monitor1 = monitor("a", "a", query: "%{a:b}", type: "composite")
      monitor2 = monitor("a", "b", query: "%{a:a}", type: "composite")
      expected << monitor1
      expected << monitor2
      assert_raises(Kennel::UnresolvableIdError) { output }.message.must_include "circular dependency"
    end

    it "fails on missing dependencies" do
      expected << monitor("a", "a", query: "%{a:nope}", type: "composite")
      assert_raises(Kennel::UnresolvableIdError) { output }.message.must_include "Unable to find"
    end

    it "fails on to-be-deleted dependencies" do
      monitors << monitor_api_response("a", "b", id: 456)
      slo = slo("a", "c", monitor_ids: ["a:b"])
      expected << slo
      assert_raises(Kennel::UnresolvableIdError) { output }.message.must_include "Unable to find"
    end

    it "updates slos before creating slo alerts to avoid failing validations" do
      expected << monitor("a", "b", foo: "bar")
      expected << slo("a", "c", foo: "bar")
      slos << slo_api_response("a", "c")
      api.expects(:create).with("monitor", anything, anything).returns(monitor_api_response("a", "b"))
      api.expects(:update).with("slo", anything, anything).returns(slo_api_response("a", "c"))
      update.changes.must_equal [
        change(:update, "slo", "a:c", "1"),
        change(:create, "monitor", "a:b", 1)
      ]
    end

    describe "pre-existing duplicate tracking IDs" do
      it "handles duplicate dashboards" do
        expected << dashboard("a", "b")
        dashboards << tagged("dashboard", {
          id: "abc1",
          description: "y\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          graphs: []
        })
        dashboards << tagged("dashboard", {
          id: "abc2",
          description: "y\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          graphs: []
        })
        # Either order is OK
        api.expects(:update).with("dashboard", "abc1", expected.first.as_json).returns(expected.first.as_json.merge(id: "abc1"))
        api.expects(:delete).with("dashboard", "abc2")
        output.must_include "Updating dashboard a:b https://app.datadoghq.com/dashboard/abc1"
        output.must_include "Deleting dashboard a:b abc2"
        output
      end

      it "handles duplicate monitors" do
        expected << monitor("a", "b")
        monitors << tagged("monitor", {
          id: 1111,
          message: "y\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          options: {}
        })
        monitors << tagged("monitor", {
          id: 2222,
          message: "y\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          options: {}
        })

        api.expects(:delete).with("monitor", 2222)
        api.expects(:update).with("monitor", 1111, expected.first.as_json).returns(expected.first.as_json.merge(id: "abc1"))

        # We must delete before we update. Rationale:
        # Datadog (for some reason) enforces monitor uniqueness on title+query+message.
        # Monitor updates can therefore fail because of this constraint.
        # Deletions will never hit this constraint. So we delete first,
        # to guarantee that the following updates will not hit the constraint.
        output.must_equal <<~OUTPUT
          Deleting monitor a:b 2222
          \e[1A\e[KDeleted monitor a:b 2222
          Updating monitor a:b https://app.datadoghq.com/monitors/1111/edit
          \e[1A\e[KUpdated monitor a:b https://app.datadoghq.com/monitors/1111/edit
        OUTPUT
      end
    end

    describe "with project_filter" do
      let(:project_filter) { ["a"] }

      it "refuses to update tracking on resources with ids since they would be deleted by other updates" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << monitor_api_response("b", "b", id: 123)
        e = assert_raises(RuntimeError) { output }
        # NOTE: we never reach the actual raise since updating tracking ids is not supported
        e.message.must_equal "Unable to find existing monitor with id 123\nIf the monitor was deleted, remove the `id: -> { 123 }` line."
      end

      it "removes tracking from partial updates with ids if they would be deleted by other branches" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << monitor_api_response("a", "b", id: 123).merge(message: "An innocent monitor", tracking_id: nil)
        api.expects(:update).with { |_, _, data| data[:message].must_equal "@slack-foo" }
        output.must_equal <<~TXT
          Updating monitor a:b https://app.datadoghq.com/monitors/123/edit
          \e[1A\033[KUpdated monitor a:b https://app.datadoghq.com/monitors/123/edit
        TXT
      end

      it "allows partial updates on monitors with ids when it does not modify tracking field" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << monitor_api_response("a", "b", id: 123)
        api.expects(:update)
        output
      end

      it "allows partial updates on monitors with ids when it does not update tracking id" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << monitor_api_response("a", "b", id: 123).merge(message: "An innocent monitor -- Managed by kennel a:b")
        api.expects(:update)
        output
      end

      it "allows partial updates on monitors without ids" do
        expected << monitor("a", "b", foo: "bar")
        monitors << monitor_api_response("a", "b", id: 123)
        api.expects(:update)
        output
      end
    end

    describe "synthetics" do
      it "can resolve a monitor id from an existing synthetic" do
        synthetics << tagged("synthetics/tests", {
          id: 123,
          monitor_id: 456,
          Kennel::Models::SyntheticTest::TRACKING_FIELD => "-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          tags: ["foo"]
        })

        synthetic = synthetic("a", "b", tags: ["foo"])
        slo = slo("a", "c", monitor_ids: ["a:b"])

        expected << synthetic
        expected << slo

        api.expects(:create)
          .with("slo", slo.as_json)
          .returns(slo_api_response("a", "c", slo.as_json.merge(id: 1000)))

        output.must_equal "Creating slo a:c\n\e[1A\e[KCreated slo a:c https://app.datadoghq.com/slo?slo_id=1000\n"
        slo.as_json[:monitor_ids].must_equal [456]
      end

      it "can resolve a monitor id from a new synthetic" do
        synthetic = synthetic("a", "b", tags: ["foo"])
        slo = slo("a", "c", monitor_ids: ["a:b"])

        expected << synthetic
        expected << slo

        api.expects(:create)
          .with("synthetics/tests", synthetic.as_json)
          .returns(tagged("synthetics/tests", synthetic.as_json.merge(id: 1001, monitor_id: 456, message: "\n-- Managed by kennel a:b")))
        api.expects(:create)
          .with("slo", slo.as_json)
          .returns(slo_api_response("a", "c", slo.as_json.merge(id: 1000)))

        output.must_equal <<~OUTPUT
          Creating synthetics/tests a:b
          \e[1A\e[KCreated synthetics/tests a:b https://app.datadoghq.com/synthetics/details/1001
          Creating slo a:c
          \e[1A\e[KCreated slo a:c https://app.datadoghq.com/slo?slo_id=1000
        OUTPUT
        slo.as_json[:monitor_ids].must_equal [456]
      end
    end

    describe "dashboards" do
      it "can update dashboards" do
        expected << dashboard("a", "b", id: "abc")
        dashboards << tagged("dashboard", {
          id: "abc",
          description: "y\n-- Managed by kennel test_project:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          graphs: []
        })
        api.expects(:update).with("dashboard", "abc", expected.first.as_json).returns(expected.first.as_json.merge(id: "abc"))
        output.must_equal <<~TXT
          Updating dashboard a:b https://app.datadoghq.com/dashboard/abc
          \e[1A\033[KUpdated dashboard a:b https://app.datadoghq.com/dashboard/abc
        TXT
      end

      it "can create dashboards" do
        expected << dashboard("a", "b")
        api.expects(:create).with("dashboard", anything).returns(tagged("dashboard", id: "abc"))
        output.must_equal <<~TXT
          Creating dashboard a:b
          \e[1A\033[KCreated dashboard a:b https://app.datadoghq.com/dashboard/abc
        TXT
      end
    end
  end
end
