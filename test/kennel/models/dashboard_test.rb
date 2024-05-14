# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Dashboard do
  define_test_classes

  # TODO: move into define_test_classes
  class TestDashboard < Kennel::Models::Dashboard
  end

  def dashboard(extra = {})
    TestDashboard.new(project, { title: -> { "Hello" }, layout_type: -> { "ordered" } }.merge(extra))
  end

  let(:project) { TestProject.new }
  let(:id_map) { Kennel::IdMap.new }
  let(:expected_json) do
    {
      layout_type: "ordered",
      title: "Hello🔒",
      description: "",
      template_variables: [],
      template_variable_presets: nil,
      widgets: [],
      reflow_type: "auto",
      tags: ["team:test-team"]
    }
  end
  let(:dashboard_with_requests) do
    dashboard(
      widgets: -> { [{ definition: { requests: [{ q: "foo", display_type: "area" }], type: "timeseries", title: "bar" } }] }
    )
  end
  let(:expected_json_with_requests) do
    expected_json.merge(
      widgets: [
        {
          definition: {
            requests: [{ q: "foo", display_type: "area" }],
            type: "timeseries",
            title: "bar"
          }
        }
      ]
    )
  end

  describe "#build_json" do
    it "renders" do
      dashboard.build_json.must_equal(expected_json)
    end

    it "renders requests" do
      dashboard_with_requests.build_json.must_equal expected_json_with_requests
    end

    it "adds ID when given" do
      dashboard(id: -> { "abc" }).build_json.must_equal expected_json.merge(id: "abc")
    end

    it "can resolve q from metadata" do
      expected_json_with_requests[:widgets][0][:definition][:requests][0][:metadata] = [{ expression: "foo" }]
      dashboard(
        widgets: -> { [{ definition: { requests: [{ q: :metadata, display_type: "area", metadata: [{ expression: "foo" }] }], type: "timeseries", title: "bar" } }] }
      ).build_json.must_equal(expected_json_with_requests)
    end

    it "does not add reflow for free" do
      expected_json[:layout_type] = "free"
      expected_json.delete(:reflow_type)
      dashboard(layout_type: -> { "free" }).build_json.must_equal(expected_json)
    end

    describe "definitions" do
      it "can add definitions" do
        dashboard(definitions: -> { [["bar", "timeseries", "area", "foo"]] }).build_json.must_equal expected_json_with_requests
      end

      it "can add toplists" do
        json = dashboard(definitions: -> { [["bar", "toplist", nil, "foo"]] }).build_json
        json[:widgets][0][:definition][:requests][0].must_equal q: "foo"
      end

      it "can add raw widgets to mix into definitions" do
        json = dashboard(definitions: -> { [{ leave: "this" }] }).build_json
        json[:widgets][0].must_equal leave: "this"
      end

      it "fails with too little args" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area"]] }).build_json
        end
      end

      it "fails with many args" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", {}, 1]] }).build_json
        end
      end

      it "fails with non-hash options" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", 1]] }).build_json
        end
      end

      it "fails with unknown options" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", { a: 1 }]] }).build_json
        end
      end
    end

    describe "template_variable_presets" do
      it "doesn't complain on sorted template_variable_presets" do
        dashboard(template_variable_presets: -> { [{ name: "A" }, { name: "B" }] }).build_json
      end

      it "complains when datadog would created a diff by sorting template_variable_presets" do
        validation_errors_from(dashboard(template_variable_presets: -> { [{ name: "B" }, { name: "A" }] }))
          .must_equal ["template_variable_presets must be sorted by name"]
      end
    end

    describe "tags" do
      it "does not add non-team tags, mirroring datadogs validation" do
        dashboard(tags: -> { ["foo"] }).build_json[:tags].must_equal []
      end
    end
  end

  describe "#resolve_linked_tracking_ids" do
    def resolve(force: false)
      dashboard_with_requests.resolve_linked_tracking_ids!(id_map, force: force)
      dashboard_with_requests.as_json[:widgets][0][:definition]
    end

    let(:definition) { dashboard_with_requests.as_json[:widgets][0][:definition] }

    before { dashboard_with_requests.build }

    it "does nothing for regular widgets" do
      resolve.keys.must_equal [:requests, :type, :title]
    end

    it "ignores widgets without definition" do
      dashboard_with_requests.build
      dashboard_with_requests.as_json[:widgets][0].delete :definition
      resolve.must_be_nil
    end

    it "ignores unknown widget types" do
      definition[:type] = "unknown"
      resolve.keys.must_equal [:requests, :type, :title]
    end

    describe "uptime" do
      before { definition[:type] = "uptime" }

      it "does not change without monitor" do
        refute resolve.key?(:monitor_ids)
      end

      it "does not change with id" do
        definition[:monitor_ids] = [123]
        resolve[:monitor_ids].must_equal [123]
      end

      it "resolves full id" do
        definition[:monitor_ids] = ["#{project.kennel_id}:b"]
        id_map.set("monitor", "a:c", 1)
        id_map.set("monitor", "#{project.kennel_id}:b", 123)
        resolved = resolve
        resolved[:monitor_ids].must_equal [123]
      end

      it "fail hard when id is still missing after dependent monitors were created by syncer" do
        definition[:monitor_ids] = ["missing:the_id"]
        id_map.set("monitor", "missing:the_id", Kennel::IdMap::NEW)
        e = assert_raises Kennel::UnresolvableIdError do
          resolve(force: true)
        end
        e.message.must_include "circular dependency"
      end
    end

    describe "alert_graph" do
      before { definition[:type] = "alert_graph" }

      it "does not change the alert widget without monitor" do
        refute resolve.key?(:alert_id)
      end

      it "does not change the alert widget with a string encoded id" do
        definition[:alert_id] = "123"
        resolve[:alert_id].must_equal "123"
      end

      it "resolves the alert widget with full id" do
        definition[:alert_id] = "#{project.kennel_id}:b"
        id_map.set("monitor", "a:c", 1)
        id_map.set("monitor", "#{project.kennel_id}:b", 123)
        resolved = resolve
        resolved[:alert_id].must_equal "123"
      end

      it "does not fail hard when id is missing to not break when adding new monitors" do
        definition[:alert_id] = "a:b"
        id_map.set("monitor", "a:b", Kennel::IdMap::NEW)
        resolve[:alert_id].must_equal "a:b"
      end
    end

    describe "slo" do
      before { definition[:type] = "slo" }

      it "does not modify regular ids" do
        definition[:slo_id] = "abcdef1234567"
        resolve[:slo_id].must_equal "abcdef1234567"
      end

      it "resolves the slo widget with full id" do
        definition[:slo_id] = "#{project.kennel_id}:b"
        id_map.set("slo", "a:c", "1")
        id_map.set("slo", "#{project.kennel_id}:b", "123")
        resolved = resolve
        resolved[:slo_id].must_equal "123"
      end

      it "resolves nested slo widget with full id" do
        definition[:widgets] = [{ definition: { slo_id: "#{project.kennel_id}:b", type: "slo" } }]
        id_map.set("slo", "a:c", "1")
        id_map.set("slo", "#{project.kennel_id}:b", "123")
        resolved = resolve
        resolved[:widgets][0][:definition][:slo_id].must_equal "123"
      end
    end

    describe "timeseries" do
      before do
        definition[:requests] << {
          queries: [
            { data_source: "metrics", query: "avg:system.cpu.user{*}" },
            { data_source: "slo", slo_id: nil }
          ]
        }
      end

      it "ignores missing ids" do
        assert_nil resolve[:requests].last[:queries].last[:slo_id]
      end

      it "does not modify regular ids" do
        definition[:requests].last[:queries].last[:slo_id] = "abcdef1234567"
        resolve[:requests].last[:queries].last[:slo_id].must_equal "abcdef1234567"
      end

      it "resolves the slo widget with full id" do
        definition[:requests].last[:queries].last[:slo_id] = "#{project.kennel_id}:b"
        id_map.set("slo", "a:c", "1")
        id_map.set("slo", "#{project.kennel_id}:b", "123")
        resolved = resolve
        resolved[:requests].last[:queries].last[:slo_id].must_equal "123"
      end
    end
  end

  describe "#diff" do
    def call(d, ...)
      d.build unless d.as_json
      d.diff(...)
    end

    it "is empty" do
      call(dashboard, expected_json).must_equal []
    end

    it "always sets template variables, since not setting them makes them nil on datadog side" do
      expected_json.delete :template_variables
      call(dashboard, expected_json).must_equal [["+", "template_variables", []]]
    end

    it "ignores author_*" do
      call(dashboard, expected_json.merge(author_handle: "a", author_name: "b")).must_equal []
    end

    it "ignores widget ids" do
      json = expected_json_with_requests
      json[:widgets][0][:id] = 123
      call(dashboard_with_requests, json).must_equal []
    end

    it "ignores default styles" do
      json = expected_json_with_requests
      json[:widgets][0][:definition][:requests][0][:style] = { line_width: "normal", palette: "dog_classic", line_type: "solid" }
      call(dashboard_with_requests, json).must_equal []
    end

    it "ignores in nested widgets" do
      definition = {
        requests: [{ q: "foo", display_type: "area" }],
        display_type: "timeseries",
        title: "bar"
      }
      widgets = [{ definition: { title: "Foo", type: "group", layout_type: "ordered", widgets: [{ definition: definition }] } }]
      expected_json[:widgets] = deep_dup(widgets)
      expected_json[:widgets][0][:id] = 123
      expected_json[:widgets][0][:definition][:widgets][0][:id] = 123

      call(dashboard(widgets: -> { widgets }), expected_json).must_equal []
    end

    it "ignores when only one side has widgets" do
      widgets = Array.new(3) { { id: 1, definition: { title: "Foo", widgets: [{ id: 2 }] } } }
      expected_json[:widgets] = widgets
      call(dashboard(widgets: -> { [] }), expected_json).inspect.wont_include ":id"
    end

    it "ignores conditional_formats ordering" do
      formats = [{ value: 1 }, { foo: "bar" }, { value: "2" }]
      old = formats.dup

      json = expected_json_with_requests
      json[:widgets][0][:definition][:conditional_formats] = formats

      dash = dashboard_with_requests
      dash.build[:widgets][0][:definition][:conditional_formats] = formats.reverse

      call(dash, json).must_equal []

      formats.must_equal old, "not in-place modified"
    end

    it "ignores note defaults" do
      json = expected_json
      json[:widgets] << {
        definition: {
          type: "note",
          content: "C",
          text_align: "left",
          background_color: "white",
          font_size: "14",
          show_tick: false,
          tick_edge: "left",
          tick_pos: "50%"
        }
      }
      call(dashboard(
             widgets: -> { [{ definition: { type: "note", content: "C" } }] }
           ), json).must_equal []
    end

    describe "reflow" do
      it "ignore reflow on ordered" do
        call(dashboard(reflow_type: -> { "auto" }), expected_json).must_equal []
      end

      it "does not ignore reflow on free" do
        d = dashboard(layout_type: -> { "free" }, reflow_type: -> { "auto" })
        call(d, expected_json).must_equal [["~", "layout_type", "ordered", "free"]]
      end
    end

    describe "with missing default" do
      let(:json) { expected_json_with_requests }
      before { json[:widgets][0][:definition][:legend_size] = "0" }

      it "ignores timeseries defaults" do
        call(dashboard_with_requests, json).must_equal []
      end

      it "does not ignore diff for different types" do
        json[:widgets][0][:definition][:show_legend] = false
        json[:widgets][0][:definition][:type] = "note"
        call(dashboard_with_requests, json).must_include ["-", "widgets[0].definition.show_legend", false]
      end
    end
  end

  describe ".normalize" do
    it "can clean up import" do
      actual = expected_json_with_requests
      actual[:widgets][0][:definition][:legend_size] = "0"
      Kennel::Models::Dashboard.normalize({}, actual)
      refute actual[:widgets][0][:definition].key?(:legend_size)
    end
  end

  describe "#url" do
    it "shows path" do
      Kennel::Models::Dashboard.url(111).must_equal "https://app.datadoghq.com/dashboard/111"
    end

    it "shows full url" do
      with_env DATADOG_SUBDOMAIN: "foobar" do
        Kennel::Models::Dashboard.url(111).must_equal "https://foobar.datadoghq.com/dashboard/111"
      end
    end
  end

  describe "#validate_update!" do
    it "allows update of title" do
      dashboard.validate_update!([["~", "title", "foo", "bar"]])
    end

    it "disallows update of layout_type" do
      e = assert_raises Kennel::DisallowedUpdateError do
        dashboard.validate_update!([["~", "layout_type", "foo", "bar"]])
      end
      e.message.must_match(/datadog.*allow.*layout_type/i)
    end
  end

  describe ".api_resource" do
    it "is dashboard" do
      Kennel::Models::Dashboard.api_resource.must_equal "dashboard"
    end
  end

  describe ".parse_url" do
    it "parses" do
      url = "https://app.datadoghq.com/dashboard/bet-foo-bar?from_ts=1585064592575&to_ts=1585068192575&live=true"
      Kennel::Models::Dashboard.parse_url(url).must_equal "bet-foo-bar"
    end

    it "fails to parse other" do
      url = "https://app.datadoghq.com/monitors/123"
      Kennel::Models::Dashboard.parse_url(url).must_be_nil
    end
  end

  describe ".ignore_request_defaults" do
    let(:valid) { { definition: { requests: [{ c: 1 }] } } }
    let(:default_style) { { line_width: "normal", palette: "dog_classic", line_type: "solid" } }

    it "does not change valid" do
      copy = deep_dup(valid)
      Kennel::Models::Dashboard.send(:ignore_request_defaults, valid, valid)
      valid.must_equal copy
    end

    it "removes defaults" do
      copy = deep_dup(valid)
      valid.dig(:definition, :requests, 0)[:style] = default_style
      Kennel::Models::Dashboard.send(:ignore_request_defaults, valid, valid)
      valid.must_equal copy
    end

    it "removes defaults when only a single side is given" do
      copy = deep_dup(valid)
      other = deep_dup(valid)
      copy.dig(:definition, :requests, 0)[:style] = default_style
      other.dig(:definition, :requests).pop
      Kennel::Models::Dashboard.send(:ignore_request_defaults, copy, other)
      copy.must_equal valid
    end

    it "does not remove non-defaults" do
      valid.dig(:definition, :requests, 0)[:style] = { foo: "bar" }
      copy = deep_dup(valid)
      Kennel::Models::Dashboard.send(:ignore_request_defaults, valid, valid)
      valid.must_equal copy
    end

    it "skips newly added requests" do
      copy = deep_dup(valid)
      copy.dig(:definition, :requests).clear
      Kennel::Models::Dashboard.send(:ignore_request_defaults, valid, copy)
      valid.must_equal definition: { requests: [{ c: 1 }] }
      copy.must_equal definition: { requests: [] }
    end
  end
end
