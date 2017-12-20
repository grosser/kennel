# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Dash do
  class TestDash < Kennel::Models::Dash
  end

  def dash(extra = {})
    TestDash.new(project, { title: -> { "Hello" } }.merge(extra))
  end

  let(:project) { TestProject.new }
  let(:expected_json) do
    {
      id: nil,
      title: "Hello🔒",
      description: "",
      read_only: false,
      template_variables: [],
      graphs: []
    }
  end
  let(:expected_json_with_graphs) do
    expected_json.merge(
      graphs: [
        {
          title: "TI",
          definition: { viz: "V", requests: [{ q: "Q", type: "TY", conditional_formats: [] }], autoscale: true }
        }
      ]
    )
  end

  describe "#as_json" do
    it "renders" do
      dash.as_json.must_equal(expected_json)
    end

    it "renders graphs and backfills common fields" do
      dash(
        graphs: -> { [{ definition: { requests: [{ q: "bar" }] } }] }
      ).as_json.must_equal(
        expected_json.merge(
          graphs: [{ definition: { requests: [{ q: "bar", conditional_formats: [] }], autoscale: true } }]
        )
      )
    end

    it "does not backfill false autoscale" do
      dash(
        graphs: -> { [{ definition: { q: "foo", requests: [], autoscale: false } }] }
      ).as_json.must_equal(
        expected_json.merge(
          graphs: [{ definition: { q: "foo", requests: [], autoscale: false } }]
        )
      )
    end

    it "does not backfill set conditional_formats" do
      dash(
        graphs: -> { [{ definition: { requests: [{ q: "bar", conditional_formats: [123] }] } }] }
      ).as_json.must_equal(
        expected_json.merge(
          graphs: [{ definition: { requests: [{ q: "bar", conditional_formats: [123] }], autoscale: true } }]
        )
      )
    end

    it "adds definitions as graphs" do
      dash(
        definitions: -> { [["TI", "V", "TY", "Q"]] }
      ).as_json.must_equal(
        expected_json.merge(
          graphs: [
            {
              title: "TI",
              definition: { viz: "V", requests: [{ q: "Q", type: "TY", conditional_formats: [] }], autoscale: true }
            }
          ]
        )
      )
    end

    it "adds definitions as graphs with multiple queries" do
      dash(
        definitions: -> { [["TI", "V", "TY", ["Q", "Q2"]]] }
      ).as_json.must_equal(
        expected_json.merge(
          graphs: [
            {
              title: "TI",
              definition: {
                viz: "V",
                requests: [
                  { q: "Q", type: "TY", conditional_formats: [] },
                  { q: "Q2", type: "TY", conditional_formats: [] }
                ],
                autoscale: true
              }
            }
          ]
        )
      )
    end

    it "expands template_variables" do
      dash(
        template_variables: -> { ["foo"] }
      ).as_json.must_equal(
        expected_json.merge(
          template_variables: [{ default: "*", prefix: "foo", name: "foo" }]
        )
      )
    end

    it "fails when not using all template variables" do
      e = assert_raises(RuntimeError) do
        dash(
          definitions: -> { [["TI", "V", "TY", "Q"], ["TI", "V", "TY", "Q2"]] },
          template_variables: -> { ["foo", "bar"] }
        ).as_json
      end
      e.message.must_equal "test_project:test_dash queries Q, Q2 must use the template variables $foo, $bar"
    end
  end

  describe "#diff" do
    it "is nil when empty" do
      dash.diff(expected_json).must_be_nil
    end

    it "does not compare unchangable resource" do
      dash.diff(expected_json.merge(resource: "dash")).must_be_nil
    end

    it "does not compare readonly created_by" do
      dash.diff(expected_json.merge(created_by: "dash")).must_be_nil
    end

    it "compares important fields" do
      dash.diff(expected_json.merge(title: "Wut")).must_equal([["~", "title", "Wut", "Hello🔒"]])
    end

    it "does not compare randomly added status" do
      expected_json_with_graphs[:graphs][0][:definition][:status] = "done"
      dash(definitions: -> { [["TI", "V", "TY", "Q"]] }).diff(expected_json_with_graphs).must_be_nil
    end

    it "does not compare randomly added aggregator" do
      expected_json_with_graphs[:graphs][0][:definition][:requests][0][:aggregator] = "avg"
      dash(definitions: -> { [["TI", "V", "TY", "Q"]] }).diff(expected_json_with_graphs).must_be_nil
    end

    it "does not compare missing template_variables" do
      expected_json.delete(:template_variables)
      dash.diff(expected_json).must_be_nil
    end
  end

  describe "#url" do
    it "shows path" do
      dash.url(111).must_equal "/dash/111"
    end

    it "shows full url" do
      with_env DATADOG_SUBDOMAIN: "foobar" do
        dash.url(111).must_equal "https://foobar.datadoghq.com/dash/111"
      end
    end
  end

  describe ".api_resource" do
    it "is dash" do
      Kennel::Models::Dash.api_resource.must_equal "dash"
    end
  end
end
