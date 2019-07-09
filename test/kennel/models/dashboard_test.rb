# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Dashboard do
  class TestDashboard < Kennel::Models::Dashboard
  end

  def dashboard(extra = {})
    TestDashboard.new(project, { title: -> { "Hello" }, layout_type: -> { "ordered" } }.merge(extra))
  end

  let(:project) { TestProject.new }
  let(:expected_json) do
    {
      title: "Hello🔒",
      layout_type: "ordered",
      description: "",
      template_variables: [],
      widgets: []
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
      dashboard.as_json.must_equal(expected_json)
    end

    it "caches" do
      d = dashboard
      d.as_json.object_id.must_equal(d.as_json.object_id)
    end

    it "renders requests" do
      dashboard_with_requests.as_json.must_equal expected_json_with_requests
    end

    it "can ignore validations" do
      dashboard(widgets: -> { [{ definition: { "foo" => 1 } }] }, validate: -> { false }).as_json
    end

    it "adds ID when given" do
      dashboard(id: -> { "abc" }).as_json.must_equal expected_json.merge(id: "abc")
    end

    describe "definitions" do
      it "can add definitions" do
        dashboard(definitions: -> { [["bar", "timeseries", "area", "foo"]] }).as_json.must_equal expected_json_with_requests
      end

      it "can add toplists" do
        json = dashboard(definitions: -> { [["bar", "toplist", nil, "foo"]] }).as_json
        json[:widgets][0][:definition][:requests][0].must_equal q: "foo"
      end

      it "fails with too little args" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area"]] }).as_json
        end
      end

      it "fails with many args" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", {}, 1]] }).as_json
        end
      end

      it "fails with non-hash options" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", 1]] }).as_json
        end
      end

      it "fails with unknown options" do
        assert_raises ArgumentError do
          dashboard(definitions: -> { [["bar", "timeseries", "area", "foo", { a: 1 }]] }).as_json
        end
      end
    end
  end

  describe "#resolve_linked_tracking_ids" do
    let(:definition) { dashboard_with_requests.as_json[:widgets][0][:definition] }

    def resolve(map = {})
      dashboard_with_requests.resolve_linked_tracking_ids(map)
      dashboard_with_requests.as_json[:widgets][0][:definition]
    end

    it "does nothing for regular widgets" do
      resolve.keys.must_equal [:requests, :type, :title]
    end

    it "ignores widgets without definition" do
      dashboard_with_requests.as_json[:widgets][0].delete :definition
      resolve.must_be_nil
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
        resolved = resolve("a:c" => 1, "#{project.kennel_id}:b" => 123)
        resolved[:monitor_ids].must_equal [123]
      end

      it "does not fail hard when id is missing to not break when adding new monitors" do
        definition[:monitor_ids] = ["missing:the_id"]
        err = Kennel::Utils.capture_stderr do
          resolve[:monitor_ids].must_equal [nil]
        end
        err.must_include "Unable to find missing:the_id in existing monitors"
      end
    end

    describe "alert_graph" do
      before { definition[:type] = "alert_graph" }

      it "does not change the alert widget without monitor" do
        refute resolve.key?(:alert_id)
      end

      it "converts integer to string" do
        definition[:alert_id] = 123
        resolve[:alert_id].must_equal "123"
      end

      it "does not change the alert widget with a string encoded id" do
        definition[:alert_id] = "123"
        resolve[:alert_id].must_equal "123"
      end

      it "resolves the alert widget with full id" do
        definition[:alert_id] = "#{project.kennel_id}:b"
        resolved = resolve("a:c" => 1, "#{project.kennel_id}:b" => 123)
        resolved[:alert_id].must_equal "123"
      end

      it "does not fail hard when id is missing to not break when adding new monitors" do
        definition[:alert_id] = "a:b"
        err = Kennel::Utils.capture_stderr do
          resolve[:alert_id].must_equal ""
        end
        err.must_include "Unable to find a:b in existing monitors"
      end
    end
  end

  describe "#diff" do
    it "is empty" do
      dashboard.diff(expected_json).must_equal []
    end

    it "ignores author_*" do
      dashboard.diff(expected_json.merge(author_handle: "a", author_name: "b")).must_equal []
    end

    it "ignores widget ids" do
      json = expected_json_with_requests
      json[:widgets][0][:id] = 123
      dashboard_with_requests.diff(json).must_equal []
    end

    it "ignores default styles" do
      json = expected_json_with_requests
      json[:widgets][0][:definition][:requests][0][:style] = { line_width: "normal", palette: "dog_classic", line_type: "solid" }
      dashboard_with_requests.diff(json).must_equal []
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

      dashboard(widgets: -> { widgets }).diff(expected_json).must_equal []
    end
  end

  describe "#url" do
    it "shows path" do
      dashboard.url(111).must_equal "/dashboard/111"
    end

    it "shows full url" do
      with_env DATADOG_SUBDOMAIN: "foobar" do
        dashboard.url(111).must_equal "https://foobar.datadoghq.com/dashboard/111"
      end
    end
  end

  describe ".api_resource" do
    it "is dashboard" do
      Kennel::Models::Dashboard.api_resource.must_equal "dashboard"
    end
  end
end
