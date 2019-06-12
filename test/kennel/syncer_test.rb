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

  def component(pid, cid, extra = {})
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

  def dash(pid, cid, extra = {})
    dash = Kennel::Models::Dash.new(
      project(pid),
      title: -> { "x" },
      description: -> { "x" },
      kennel_id: -> { cid },
      id: -> { extra[:id]&.to_s }
    )
    dash.as_json.delete_if { |k, _| ![:description, :options, :graphs, :template_variables].include?(k) }
    dash.as_json.merge!(extra)
    dash
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

  def screen(pid, cid, extra)
    screen = Kennel::Models::Screen.new(
      project(pid),
      board_title: -> { "x" },
      description: -> { "x" },
      kennel_id: -> { cid },
      id: -> { extra[:id]&.to_s }
    )
    screen.as_json.delete_if { |k, _| ![:description, :options, :widgets, :template_variables].include?(k) }
    screen.as_json.merge!(extra)
    screen
  end

  def add_identical
    expected << monitor("a", "b")
    monitors << component("a", "b")
  end

  let(:api) { stub("Api") }
  let(:monitors) { [] }
  let(:dashes) { [] }
  let(:screens) { [] }
  let(:dashboards) { [] } # TODO: individual dashboards use modified_at
  let(:expected) { [] }
  let(:project_filter) { nil }
  let(:syncer) { Kennel::Syncer.new(api, expected, project: project_filter) }

  before do
    Kennel::Progress.stubs(:print).yields
    api.stubs(:list).with("monitor", anything).returns(monitors)
    api.stubs(:list).with("dash", anything).returns(dashes: dashes)
    api.stubs(:list).with("screen", anything).returns(screenboards: screens)
    api.stubs(:list).with("dashboard", anything).returns(dashboards: dashboards)
  end

  capture_all # TODO: pass an IO to syncer so we don't have to capture all output

  describe "#plan" do
    let(:output) do
      (monitors + dashes).each { |m| m[:id] ||= 123 } # existing components always have an id
      syncer.plan
      stdout.string.gsub(/\e\[\d+m(.*)\e\[0m/, "\\1") # remove colors
    end

    it "does nothing when everything is empty" do
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "creates missing" do
      expected << monitor("a", "b")
      output.must_equal "Plan:\nCreate a:b\n"
    end

    it "ignores identical" do
      add_identical
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "ignores readonly attributes since we do not generate them" do
      expected << monitor("a", "b")
      monitors << component("a", "b", created: true)
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "ignores silencing since that is managed via the UI" do
      expected << monitor("a", "b")
      monitors << component("a", "b", options: { silenced: { "*" => 1 } })
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "updates when changed" do
      expected << monitor("a", "b", foo: "bar", bar: "foo", nested: { foo: "bar" })
      monitors << component("a", "b", foo: "baz", baz: "foo", nested: { foo: "baz" })
      output.must_equal <<~TEXT
        Plan:
        Update a:b
          -baz \"foo\" -> nil
          ~foo \"baz\" -> \"bar\"
          ~nested.foo \"baz\" -> \"bar\"
          +bar nil -> \"foo\"
      TEXT
    end

    describe "with project filter set" do
      let(:project_filter) { "a" }

      it "updates when previously unmanaged" do
        expected << monitor("a", "b", id: 123)
        monitors << component("a", "", id: 123, message: "old stuff")
        output.must_equal <<~TEXT
          Plan:
          Update a:b
            ~message \"old stuff\" -> \"@slack-foo\\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually\"
        TEXT
      end
    end

    it "shows long updates nicely" do
      expected << monitor("a", "b", foo: "something very long but not too long I do not know")
      monitors << component("a", "b", foo: "something shorter but still very long but also different")
      output.must_equal <<~TEXT
        Plan:
        Update a:b
          ~foo
            \"something shorter but still very long but also different\" ->
            \"something very long but not too long I do not know\"
      TEXT
    end

    it "shows added tags nicely" do
      expected << monitor("a", "b", tags: ["foo", "bar"])
      monitors << component("a", "b", tags: ["foo", "baz"])
      output.must_equal <<~TEXT
        Plan:
        Update a:b
          ~tags[1] \"baz\" -> \"bar\"
      TEXT
    end

    it "deletes when removed from code" do
      monitors << component("a", "b")
      output.must_equal "Plan:\nDelete a:b\n"
    end

    it "deletes newest when existing monitor was copied" do
      expected << monitor("a", "b")
      monitors << component("a", "b")
      monitors << component("a", "b", tags: ["old"])
      output.must_equal "Plan:\nDelete a:b\n"
    end

    it "does not break on nil tracking field (dashboards can have nil description)" do
      monitors << component("a", "b", message: nil)
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "leaves unmanaged alone" do
      monitors << { id: 123, message: "foo", tags: [] }
      output.must_equal "Plan:\nNothing to do\n"
    end

    it "notifies about duplicate components since they would be ignored otherwise" do
      expected << monitor("a", "b") << monitor("a", "b")
      monitors << component("a", "c") # need something to trigger lookup_map to initialize
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
      monitors << component("a", "b", id: 234)
      assert_raises(RuntimeError) { output }.message.must_equal(
        "remove \"-- Managed by kennel\" line it from message to copy a resource"
      )
    end

    describe "filter" do
      let(:syncer) { Kennel::Syncer.new(api, expected, project: "a") }

      it "does nothing when ignores changes" do
        add_identical
        expected << monitor("b", "c")
        output.must_equal "Plan:\nNothing to do\n"
      end

      it "does something when filtered changes" do
        expected << monitor("a", "c")
        output.must_equal "Plan:\nCreate a:c\n"
      end

      it "leaves unmanaged alone" do
        add_identical
        monitors << { id: 123, message: "foo", tags: [] }
        output.must_equal "Plan:\nNothing to do\n"
      end

      it "shows correct values when using invalid name" do
        expected << monitor("b", "a")
        expected << monitor("c", "a")
        e = assert_raises(RuntimeError) { output }
        e.message.must_equal <<~ERROR.strip
          a does not match any projects, try any of these:
          b
          c
        ERROR
      end
    end

    describe "dashes" do
      in_temp_dir # uses file-cache

      it "can plan for dashes" do
        expected << dash("a", "b", id: 123)
        dashes << {
          id: 123,
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          graphs: []
        }
        api.expects(:show).with("dash", 123).returns(dash: {})
        output.must_equal "Plan:\nNothing to do\n"
      end
    end

    describe "screens" do
      in_temp_dir # uses file-cache

      it "can plan for screens" do
        expected << screen("a", "b", id: 123)
        screens << {
          id: "123",
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          widgets: []
        }
        api.expects(:show).with("screen", 123).returns({})
        output.must_equal "Plan:\nNothing to do\n"
      end

      it "links tracking ids" do
        monitors << component("a", "b", id: 124)
        s = screen("a", "c", widgets: [{ type: "uptime", monitor: { id: "a:b" } }])
        expected << s
        syncer.send(:calculate_diff)
        s.as_json.dig(:widgets, 0, :monitor, :id).must_equal 124
      end
    end

    describe "dashboards" do
      in_temp_dir # uses file-cache

      it "can plan for dashboards" do
        expected << dashboard("a", "b", id: "abc")
        dashboards << {
          id: "abc",
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified_at: "2015-12-17T23:12:26.726234+00:00"
        }
        api.expects(:show).with("dashboard", "abc").returns(dashboard: { widgets: [] })
        output.must_equal "Plan:\nNothing to do\n"
      end

      it "can plan for dashes and dashboards" do
        expected << dash("a", "b", id: 123) # abc
        expected << dashboard("a", "c", id: "bcd") # old_id is fake
        dashboards << {
          id: "abc", # should be ignored
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified_at: "2015-12-17T23:12:26.726234+00:00"
        }
        dashboards << {
          id: "bcd", # should be used
          description: "x\n-- Managed by kennel a:c in test/test_helper.rb, do not modify manually",
          modified_at: "2015-12-17T23:12:26.726234+00:00"
        }
        dashes << {
          id: 123, # should be used
          new_id: "abc",
          description: "x\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00"
        }
        dashes << {
          id: 234, # should be ignored
          new_id: "bcd",
          description: "x\n-- Managed by kennel a:c in test/test_helper.rb, do not modify manually",
          modified_at: "2015-12-17T23:12:26.726234+00:00"
        }
        api.expects(:show).with("dash", 123).returns(dash: { graphs: [] })
        api.expects(:show).with("dashboard", "bcd").returns(dashboard: { widgets: [] })
        output.must_equal "Plan:\nNothing to do\n"
      end
    end

    describe "replacement" do
      before do
        expected << monitor("a", "b", id: 234, foo: "bar")
        monitors << component("a", "b", id: 234)
      end

      it "updates via replace" do
        monitors.last[:message] = "nope" # actual is not marked yet
        output.must_equal <<~TEXT
          Plan:
          Update a:b
            ~message \"nope\" -> \"@slack-foo\\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually\"
            +foo nil -> \"bar\"
        TEXT
      end

      it "can update renamed components" do
        monitors.last[:message] = "foo\n-- Managed by kennel foo:bar in foo.rb"
        output.must_equal <<~TEXT
          Plan:
          Update a:b
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
          Update a:b
            ~message
              "foo\\n-- Managed by kennel foo:bar in foo.rb" ->
              "@slack-foo\\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually"
        TEXT
      end

      it "complains when id was not found" do
        monitors.pop
        e = assert_raises(RuntimeError) { syncer.plan }
        e.message.must_equal "Unable to find existing monitor with id 234"
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
      output.must_equal "Created monitor a:b /monitors#123/edit\n"
    end

    it "sets values we do not compare on" do
      expected << monitor("a", "b", type: "event alert", options: { thresholds: { critical: 2 } })
      sent = deep_dup(expected.first.as_json)
      sent[:message] = "@slack-foo\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually".lstrip
      api.expects(:create).with("monitor", sent).returns(sent.merge(id: 123))
      output.must_equal "Created monitor a:b /monitors#123/edit\n"
    end

    it "updates" do
      expected << monitor("a", "b", foo: "bar")
      monitors << component("a", "b", id: 123)
      api.expects(:update).with("monitor", 123, expected.first.as_json).returns(expected.first.as_json.merge(id: 123))
      output.must_equal "Updated monitor a:b /monitors#123/edit\n"
    end

    it "deletes" do
      monitors << component("a", "b", id: 123)
      api.expects(:delete).with("monitor", 123).returns({})
      output.must_equal "Deleted monitor a:b 123\n"
    end

    describe "with project_filter" do
      let(:project_filter) { "a" }

      it "refuses to tag resources with ids since they would be irreversibly deleted by other branches" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << component("a", "b", id: 123).merge(message: "An innocent monitor")
        e = assert_raises(RuntimeError) { output }
        e.message.must_include "should not update"
      end

      it "allows partial updates on monitors with ids when it does not modify tracking" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << component("a", "b", id: 123)
        api.expects(:update)
        output
      end

      it "allows partial updates on monitors with ids when it does not modify tracking id" do
        expected << monitor("a", "b", foo: "bar", id: 123)
        monitors << component("a", "b", id: 123).merge(message: "An innocent monitor -- Managed by kennel a:b")
        api.expects(:update)
        output
      end
    end

    describe "dashes" do
      in_temp_dir # uses file-cache

      it "can update dashes" do
        expected << dash("a", "b", id: 123)
        dashes << {
          id: 123,
          description: "y\n-- Managed by kennel test_project:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          graphs: []
        }
        api.expects(:show).with("dash", 123).returns(dash: {})
        api.expects(:update).with("dash", 123, expected.first.as_json).returns(expected.first.as_json.merge(id: 123))
        output.must_equal "Updated dash a:b /dash/123\n"
      end

      it "can create dashes" do
        expected << dash("a", "b")
        api.expects(:create).with("dash", anything).returns(dash: { id: 123 })
        output.must_equal "Created dash a:b /dash/123\n"
      end
    end

    describe "screens" do
      in_temp_dir # uses file-cache

      it "can update screens" do
        expected << screen("a", "b", id: 123)
        screens << {
          id: 123,
          description: "y\n-- Managed by kennel a:b in test/test_helper.rb, do not modify manually",
          modified: "2015-12-17T23:12:26.726234+00:00",
          widgets: []
        }
        api.expects(:show).with("screen", 123).returns(dash: {})
        api.expects(:update).with("screen", 123, expected.first.as_json).returns(expected.first.as_json.merge(id: 123))
        output.must_equal "Updated screen a:b /screen/123\n"
      end
    end
  end
end
