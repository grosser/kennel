# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Dashboard do
  with_test_classes

  class TestDashboard < Kennel::Models::Dashboard
  end

  def dashboard(extra = {})
    TestDashboard.new(project, { title: -> { "Hello" }, layout_type: -> { "ordered" } }.merge(extra))
  end

  let(:project) { TestProject.new }
  let(:expected_json) do
    {
      layout_type: "ordered",
      title: "Hello🔒",
      description: "",
      template_variables: [],
      template_variable_presets: nil,
      widgets: [],
      reflow_type: "auto"
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

  describe "#as_json" do
    it "renders" do
      dashboard.build!.as_json.must_equal(expected_json)
    end

    it "renders requests" do
      dashboard_with_requests.build!.as_json.must_equal expected_json_with_requests
    end

    it "complains when datadog would created a diff by sorting template_variable_presets" do
      validation_error_from(dashboard(template_variable_presets: -> { [{ name: "B" }, { name: "A" }] }))
        .must_equal "template_variable_presets must be sorted by name"
    end

    it "doesn't complain on sorted template_variable_presets" do
      dashboard(template_variable_presets: -> { [{ name: "A" }, { name: "B" }] }).build!.as_json
    end

    it "adds ID when given" do
      dashboard(id: -> { "abc" }).build!.as_json.must_equal expected_json.merge(id: "abc")
    end

    it "can resolve q from metadata" do
      expected_json_with_requests[:widgets][0][:definition][:requests][0][:metadata] = [{ expression: "foo" }]
      dashboard(
        widgets: -> { [{ definition: { requests: [{ q: :metadata, display_type: "area", metadata: [{ expression: "foo" }] }], type: "timeseries", title: "bar" } }] }
      ).build!.as_json.must_equal(expected_json_with_requests)
    end

    it "does not add reflow for free" do
      expected_json[:layout_type] = "free"
      expected_json.delete(:reflow_type)
      dashboard(layout_type: -> { "free" }).build!.as_json.must_equal(expected_json)
    end

    it "adds team tags when requested" do
      project.team.class.any_instance.expects(:tag_dashboards).returns(true)
      dashboard.build!.as_json[:title].must_equal "Hello (team:test_team)🔒"
    end

    describe "definitions" do
      def prepare_error_of(expected)
        matcher = Module.new
        matcher.define_singleton_method(:===) do |caught|
          # rubocop:disable Style/CaseEquality
          Kennel::Models::Record::PrepareError === caught && expected === caught.cause
          # rubocop:enable Style/CaseEquality
        end
        matcher
      end

      it "can add definitions" do
        dashboard(definitions: -> { [["bar", "timeseries", "area", "foo"]] }).build!.as_json.must_equal expected_json_with_requests
      end

      it "can add toplists" do
        json = dashboard(definitions: -> { [["bar", "toplist", nil, "foo"]] }).build!.as_json
        json[:widgets][0][:definition][:requests][0].must_equal q: "foo"
      end

      it "can add raw widgets to mix into definitions" do
        json = dashboard(definitions: -> { [{ leave: "this" }] }).build!.as_json
        json[:widgets][0].must_equal leave: "this"
      end

      it "fails with too little args" do
        assert_raises prepare_error_of(ArgumentError) do
          dashboard(definitions: -> { [["bar", "timeseries", "area"]] }).build!.as_json
        end
      end

      it "fails with many args" do
        assert_raises prepare_error_of(ArgumentError) do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", {}, 1]] }).build!.as_json
        end
      end

      it "fails with non-hash options" do
        assert_raises prepare_error_of(ArgumentError) do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", 1]] }).build!.as_json
        end
      end

      it "fails with unknown options" do
        assert_raises prepare_error_of(ArgumentError) do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", { a: 1 }]] }).build!.as_json
        end
      end
    end
  end

  describe "#diff" do
    it "is empty" do
      dashboard.build!.diff(expected_json).must_equal []
    end

    it "always sets template variables, since not setting them makes them nil on datadog side" do
      expected_json.delete :template_variables
      dashboard.build!.diff(expected_json).must_equal [["+", "template_variables", []]]
    end

    it "ignores author_*" do
      dashboard.build!.diff(expected_json.merge(author_handle: "a", author_name: "b")).must_equal []
    end

    it "ignores widget ids" do
      json = expected_json_with_requests
      json[:widgets][0][:id] = 123
      dashboard_with_requests.build!.diff(json).must_equal []
    end

    it "ignores default styles" do
      json = expected_json_with_requests
      json[:widgets][0][:definition][:requests][0][:style] = { line_width: "normal", palette: "dog_classic", line_type: "solid" }
      dashboard_with_requests.build!.diff(json).must_equal []
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

      dashboard(widgets: -> { widgets }).build!.diff(expected_json).must_equal []
    end

    it "ignores when only one side has widgets" do
      widgets = Array.new(3) { { id: 1, definition: { title: "Foo", widgets: [{ id: 2 }] } } }
      expected_json[:widgets] = widgets
      dashboard(widgets: -> { [] }).build!.diff(expected_json).inspect.wont_include ":id"
    end

    it "ignores conditional_formats ordering" do
      formats = [{ value: 1 }, { foo: "bar" }, { value: "2" }]
      old = formats.dup

      json = expected_json_with_requests
      json[:widgets][0][:definition][:conditional_formats] = formats

      dash = dashboard_with_requests.build!

      dash.as_json[:widgets][0][:definition][:conditional_formats] = formats.reverse

      dash.diff(json).must_equal []

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
      dashboard(
        widgets: -> { [{ definition: { type: "note", content: "C" } }] }
      ).build!.diff(json).must_equal []
    end

    describe "reflow" do
      it "ignore reflow on ordered" do
        dashboard(reflow_type: -> { "auto" }).build!.diff(expected_json).must_equal []
      end

      it "does not ignore reflow on free" do
        d = dashboard(layout_type: -> { "free" }, reflow_type: -> { "auto" })
        d.build!.diff(expected_json).must_equal [["~", "layout_type", "ordered", "free"]]
      end
    end

    describe "with missing default" do
      let(:json) { expected_json_with_requests }
      before { json[:widgets][0][:definition][:show_legend] = true }

      it "ignores timeseries defaults" do
        dashboard_with_requests.build!.diff(json).must_equal []
      end

      it "does not ignore diff for different types" do
        json[:widgets][0][:definition][:show_legend] = false
        json[:widgets][0][:definition][:type] = "note"
        dashboard_with_requests.build!.diff(json).must_include ["-", "widgets[0].definition.show_legend", false]
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
