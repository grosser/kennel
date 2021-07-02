# frozen_string_literal: true
require_relative "../test_helper"
require "stringio"

SingleCov.covered!

describe Kennel::Syncer do
  def project(pid)
    project = TestProject.new
    project.define_singleton_method(:kennel_id) { pid }
    project
  end

  def monitor_api_response(pid, cid, extra = {})
    {
      tags: extra.delete(:tags) || ["service:a", "team:test_team"],
      message: "@slack-foo\n-- Managed by kennel #{pid}:#{cid} in test/test_helper.rb, do not modify manually",
      options: {}
    }.merge(extra)
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

    # make the diff simple
    monitor.as_json[:options] = {
      escalation_message: nil,
      evaluation_delay: nil
    }
    monitor.as_json.delete_if { |k, _| ![:tags, :message, :options].include?(k) }
    monitor.as_json.merge!(extra)

    monitor
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
    dash.as_json.delete_if { |k, _| ![:description, :options, :widgets, :template_variables].include?(k) }
    dash.as_json.merge!(extra)
    dash
  end

  def slo(pid, cid, extra = {})
    dash = Kennel::Models::Slo.new(
      project(pid),
      name: -> { "x" },
      description: -> { "x" },
      type: -> { "metric" },
      kennel_id: -> { cid },
      id: -> { extra[:id]&.to_s },
      thresholds: -> { [] }
    )
    # dash.as_json.delete_if { |k, _| ![:description, :options, :widgets, :template_variables].include?(k) }
    dash.as_json.merge!(extra)
    dash
  end

  def add_identical
    expected << monitor("a", "b")
    monitors << monitor_api_response("a", "b")
  end

  let(:api) { stub("Api") }
  let(:monitors) { [] }
  let(:dashboards) { [] }
  let(:slos) { [] }
  let(:expected) { [] }
  let(:project_filter) { nil }
  let(:syncer) { Kennel::Syncer.new(api, expected, project: project_filter) }

  before do
    Kennel::Progress.stubs(:print).yields
    api.stubs(:list).with("dashboard", anything).returns(dashboards: dashboards)
    api.stubs(:list).with("monitor", anything).returns(monitors)
    api.stubs(:list).with("slo", anything).returns(data: slos)
    api.stubs(:fill_details!)
  end

  capture_all # TODO: pass an IO to syncer so we don't have to capture all output

  describe "#plan" do
    let(:output) do
      (monitors + dashboards).each { |m| m[:id] ||= 123 } # existing components always have an id
      syncer.plan
      stdout.string.gsub(/\e\[\d+m(.*)\e\[0m/, "\\1") # remove colors
    end

    it "does nothing when everything is empty" do
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "creates missing" do
      expected << monitor("a", "b")
      output.must_equal "Plan:\nCreate monitor a:b\n"
    end

    it "ignores identical" do
      add_identical
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "ignores readonly attributes since we do not generate them" do
      expected << monitor("a", "b")
      monitors << monitor_api_response("a", "b", created: true)
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "ignores silencing since that is managed via the UI" do
      expected << monitor("a", "b")
      monitors << monitor_api_response("a", "b", options: { silenced: { "*" => 1 } })
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "updates when changed" do
      expected << monitor("a", "b", foo: "bar", bar: "foo", nested: { foo: "bar" })
      monitors << monitor_api_response("a", "b", foo: "baz", baz: "foo", nested: { foo: "baz" })
      output.must_equal <<~TEXT
        Plan:
        Update monitor a:b
          -baz \"foo\" -> nil
          ~foo \"baz\" -> \"bar\"
          ~nested.foo \"baz\" -> \"bar\"
          +bar nil -> \"foo\"
      TEXT
    end

    describe "with project filter set" do
      let(:project_filter) { "a" }

      it "updates without tracking when previously unmanaged" do
        expected << monitor("a", "b", id: 123)
        monitors << monitor_api_response("a", "", id: 123, message: "old stuff")
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
      monitors << monitor_api_response("a", "b")
      output.must_equal "Plan:\nDelete monitor a:b\n"
    end

    it "deletes in logical order" do
      monitors << monitor_api_response("a", "a")
      dashboards << {
        id: "abc",
        description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually"
      }
      slos << {
        id: "1",
        description: "x\n-- Managed by kennel a:c in test/test_helper.rb, do not modify manually"
      }
      output.must_equal "Plan:\nDelete dashboard a:b\nDelete slo a:c\nDelete monitor a:a\n"
    end

    it "deletes newest when existing monitor was copied" do
      expected << monitor("a", "b")
      monitors << monitor_api_response("a", "b")
      monitors << monitor_api_response("a", "b", tags: ["old"])
      output.must_equal "Plan:\nDelete monitor a:b\n"
    end

    it "does not break on nil tracking field (dashboards can have nil description)" do
      monitors << monitor_api_response("a", "b", message: nil)
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "leaves unmanaged alone" do
      monitors << { id: 123, message: "foo", tags: [] }
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "notifies about duplicate components since they would be ignored otherwise" do
      expected << monitor("a", "b") << monitor("a", "b")
      monitors << monitor_api_response("a", "c") # need something to trigger lookup_map to initialize
      e = assert_raises(RuntimeError) { output }
      e.message.must_equal "Lookup a:b is duplicated"
    end

    it "shows progress" do
      Kennel::Progress.unstub(:print)
      output.must_equal "Plan:\nNothing to do\n"
      stderr.string.gsub(/\.\.\. .*?\d\.\d+s/, "... 0.0s").must_equal "Downloading definitions ... 0.0s\nDiffing ... 0.0s\n"
    end

    it "fails when user copy-pasted existing message with kennel id since that would lead to bad updates" do
      expected << monitor("a", "b", id: 234, foo: "bar", message: "foo\n-- Managed by kennel foo:bar in foo.rb")
      monitors << monitor_api_response("a", "b", id: 234)
      assert_raises(RuntimeError) { output }.message.must_equal(
        "a:b remove \"-- Managed by kennel\" line it from message to copy a resource"
      )
    end

    describe "filter" do
      let(:syncer) { Kennel::Syncer.new(api, expected, project: "a") }

      it "does something when filtered changes" do
        expected << monitor("a", "c")
        output.must_equal "Plan:\nCreate monitor a:c\n"
      end

      it "leaves unmanaged alone" do
        add_identical
        monitors << { id: 123, message: "foo", tags: [] }
        output.must_equal "Plan:\nNothing to do\n"
      end
    end

    describe "dashboards" do
      it "can plan for dashboards" do
        expected << dashboard("a", "b", id: "abc")
        dashboards << {
          id: "abc",
          template_variables: [],
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified_at: "2015-12-17T23:12:26.726234+00:00"
        }
        api.expects(:fill_details!).with { dashboards.last[:widgets] = [] }
        output.must_equal "Plan:\nNothing to do\n"
      end
    end

    describe "slos" do
      it "can plan for slos" do
        expected << slo("a", "b", id: "abc")
        slos << {
          id: "abc",
          name: "x\u{1F512}",
          type: "metric",
          thresholds: [],
          tags: ["team:test_team", "service:a"],
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually"
        }
        output.must_equal "Plan:\nNothing to do\n"
      end
    end

    describe "replacement" do
      before do
        expected << monitor("a", "b", id: 234, foo: "bar")
        monitors << monitor_api_response("a", "b", id: 234)
      end

      it "updates via replace" do
        monitors.last[:message] = "nope" # actual is not marked yet
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message \"nope\" -> \"@slack-foo\\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually\"
            +foo nil -> \"bar\"
        TEXT
      end

      it "can update renamed components" do
        monitors.last[:message] = "foo\n-- Managed by kennel foo:bar in foo.rb"
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message
              "foo\\n-- Managed by kennel foo:bar in foo.rb" ->
              "@slack-foo\\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually"
            +foo nil -> \"bar\"
        TEXT
      end

      it "can update renamed components without other diff" do
        expected.last.as_json.delete(:foo)
        monitors.last[:message] = "foo\n-- Managed by kennel foo:bar in foo.rb"
        output.must_equal <<~TEXT
          Plan:
          Update monitor a:b
            ~message
              "foo\\n-- Managed by kennel foo:bar in foo.rb" ->
              "@slack-foo\\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually"
        TEXT
      end

      it "complains when id was not found" do
        monitors.pop
        e = assert_raises(RuntimeError) { syncer.plan }
        e.message.must_equal "Unable to find existing monitor with id 234\nIf the monitor was deleted, remove the `id: -> { 234 }` line."
      end
    end
  end

  describe "#confirm" do
    before do
      expected << monitor("a", "b")
      STDIN.stubs(:tty?).returns(true)
    end

    it "confirms on y" do
      STDIN.expects(:gets).returns("y\n")
      assert syncer.confirm
      stderr.string.must_include "\e[31mExecute Plan ? -  press 'y' to continue: \e[0m"
    end

    it "confirms when automated" do
      STDIN.stubs(:tty?).returns(false)
      assert syncer.confirm
    end

    it "confirms when on CI" do
      with_env CI: "true" do
        assert syncer.confirm
      end
    end

    it "denies on n" do
      STDIN.expects(:gets).returns("n\n")
      refute syncer.confirm
    end

    it "denies when nothing changed" do
      expected.clear
      refute syncer.confirm
      stdout.string.must_equal ""
    end
  end

  describe "#update" do
    let(:output) do
      syncer.update
      stdout.string
    end

    it "does nothing when nothing is to do" do
      output.must_equal ""
    end

    it "creates" do
      expected << monitor("a", "b")
      api.expects(:create).with("monitor", expected.first.as_json).returns(expected.first.as_json.merge(id: 123))
      output.must_equal <<~TXT
        Creating monitor a:b
        \e[1A\033[KCreated monitor a:b /monitors#123/edit
      TXT
    end

    it "sets values we do not compare on" do
      expected << monitor("a", "b", type: "event alert", options: { thresholds: { critical: 2 } })
      sent = deep_dup(expected.first.as_json)
      sent[:message] = "@slack-foo\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually".lstrip
      api.expects(:create).with("monitor", sent).returns(sent.merge(id: 123))
      output.must_equal <<~TXT
        Creating monitor a:b
        \e[1A\033[KCreated monitor a:b /monitors#123/edit
      TXT
    end

    it "updates" do
      expected << monitor("a", "b", foo: "bar")
      monitors << monitor_api_response("a", "b", id: 123)
      api.expects(:update).with("monitor", 123, expected.first.as_json).returns(expected.first.as_json.merge(id: 123))
      output.must_equal <<~TXT
        Updating monitor a:b /monitors#123/edit
        \e[1A\033[KUpdated monitor a:b /monitors#123/edit
      TXT
    end

    it "deletes" do
      monitors << monitor_api_response("a", "b", id: 123)
      api.expects(:delete).with("monitor", 123).returns({})
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
      api.expects(:create)
        .with("monitor", monitor.as_json)
        .returns(monitor.as_json.merge(id: 1, message: "\n-- Managed by kennel a:b"))
      api.expects(:create)
        .with(
          "slo",
          slo.as_json.merge(
            monitor_ids: [1],
            description: "x\n-- Managed by kennel a:c in test/test_helper.rb, do not modify manually"
          )
        ).returns(id: 2)
      output.must_equal <<~TXT
        Creating monitor a:b
        \e[1A\033[KCreated monitor a:b /monitors#1/edit
        Creating slo a:c
        \e[1A\033[KCreated slo a:c /slo?slo_id=2
      TXT
    end

    it "fails on circular dependencies" do
      monitor1 = monitor("a", "a", query: "%{a:b}", type: "composite")
      monitor2 = monitor("a", "b", query: "%{a:a}", type: "composite")
      expected << monitor1
      expected << monitor2
      assert_raises(Kennel::ValidationError) { output }.message.must_include "circular dependency"
    end

    it "fails on missing dependencies" do
      expected << monitor("a", "a", query: "%{a:nope}", type: "composite")
      assert_raises(Kennel::ValidationError) { output }.message.must_include "Unable to find"
    end

    describe "with project_filter" do
      let(:project_filter) { "a" }

      it "refuses to update tracking on resources with ids since they would be deleted by other updates" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << monitor_api_response("a", "b", id: 123).merge(message: "An innocent monitor -- Managed by kennel b:b")
        e = assert_raises(RuntimeError) { output }
        # NOTE: we never reach the actual raise since updating tracking ids is not supported
        e.message.must_equal "Unable to find existing monitor with id 123\nIf the monitor was deleted, remove the `id: -> { 123 }` line."
      end

      it "removes tracking from partial updates with ids if they would be deleted by other branches" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << monitor_api_response("a", "b", id: 123).merge(message: "An innocent monitor")
        api.expects(:update).with { |_, _, data| data[:message].must_equal "@slack-foo" }
        output.must_equal <<~TXT
          Updating monitor a:b /monitors#123/edit
          \e[1A\033[KUpdated monitor a:b /monitors#123/edit
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

    describe "dashboards" do
      it "can update dashboards" do
        expected << dashboard("a", "b", id: "abc")
        dashboards << {
          id: "abc",
          description: "y\n-- Managed by kennel test_project:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          graphs: []
        }
        api.expects(:update).with("dashboard", "abc", expected.first.as_json).returns(expected.first.as_json.merge(id: "abc"))
        output.must_equal <<~TXT
          Updating dashboard a:b /dashboard/abc
          \e[1A\033[KUpdated dashboard a:b /dashboard/abc
        TXT
      end

      it "can create dashboards" do
        expected << dashboard("a", "b")
        api.expects(:create).with("dashboard", anything).returns(id: "abc")
        output.must_equal <<~TXT
          Creating dashboard a:b
          \e[1A\033[KCreated dashboard a:b /dashboard/abc
        TXT
      end
    end
  end
end
