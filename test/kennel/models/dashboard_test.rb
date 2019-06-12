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
      widgets: -> { [{ definition: { requests: [{ q: "foo", display_type: "area" }], display_type: "timeseries", title: "bar" } }] }
    )
  end
  let(:expected_json_with_requests) do
    expected_json.merge(
      widgets: [
        {
          definition: {
            requests: [{ q: "foo", display_type: "area" }],
            display_type: "timeseries",
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
