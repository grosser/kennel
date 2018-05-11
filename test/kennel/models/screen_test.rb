# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Screen do
  class TestScreen < Kennel::Models::Screen
  end

  def screen(extra = {})
    TestScreen.new(project, { board_title: -> { "Hello" } }.merge(extra))
  end

  let(:project) { TestProject.new }
  let(:expected_json) do
    {
      id: nil,
      board_title: "Hello🔒",
      description: "",
      template_variables: [],
      widgets: []
    }
  end
  let(:default_widget) { { title_size: 16, title_align: "left", height: 20, width: 30 }.freeze }

  describe "#as_json" do
    it "renders" do
      screen.as_json.must_equal(expected_json)
    end

    it "renders widgets and backfills common fields" do
      screen(
        widgets: -> {
          [{
            title_text: "Hello",
            type: "timeseries",
            x: 0,
            y: 0,
            tile_def: {
              viz: "timeseries",
              requests: [
                {
                  q: "avg:foo.bar",
                  aggregator: "avg",
                  type: "area"
                }
              ]
            }
          }]
        }
      ).as_json.must_equal(
        expected_json.merge(
          widgets: [
            {
              title_size: 16,
              title_align: "left",
              height: 20,
              width: 30,
              title: true,
              legend: false,
              legend_size: "0",
              timeframe: "1h",
              type: "timeseries",
              title_text: "Hello",
              x: 0,
              y: 0,
              tile_def: {
                viz: "timeseries",
                requests: [
                  {
                    q: "avg:foo.bar",
                    aggregator: "avg",
                    type: "area",
                    conditional_formats: []
                  }
                ],
                autoscale: true
              }
            }
          ]
        )
      )
    end

    it "does not set autoscale when it was set to false" do
      screen(widgets: -> { [{ tile_def: { autoscale: false, requests: [] } }] }).as_json
        .dig(:widgets, 0, :tile_def, :autoscale)
        .must_equal false
    end

    it "caches" do
      s = screen
      s.as_json.object_id.must_equal s.as_json.object_id
    end

    it "does not render board_id to avoid useless diff when user copy-pasted api reply" do
      screen(widgets: -> { [{ board_id: 123 }] }).as_json.must_equal(expected_json.merge(widgets: [default_widget]))
    end
  end

  describe "#diff" do
    it "is nil when empty" do
      screen.diff(expected_json).must_be_nil
    end

    it "does not compare read-only widget board_id field" do
      screen(widgets: -> { [{ board_id: 123 }] }).diff(expected_json.merge(widgets: [default_widget.dup])).must_be_nil
    end

    it "does not compare read-only disableCog field" do
      screen.diff(expected_json.merge(disableCog: true)).must_be_nil
    end

    it "can diff text tiles" do
      screen(widgets: -> { [{ text: "A", type: "free_text" }] }).diff(expected_json)
    end

    it "can diff unknown to be future proof" do
      expected = expected_json.merge(
        widgets: [{ title_size: 16, title_align: "left", height: 20, width: 30, text: "A", type: "foo" }]
      )
      screen(widgets: -> { [{ text: "A", type: "foo" }] }).diff(expected).must_be_nil
    end

    it "compares important fields" do
      screen.diff(expected_json.merge(board_title: "Wut")).must_equal([["~", "board_title", "Wut", "Hello🔒"]])
    end

    it "does not compare missing template_variables" do
      expected_json.delete(:template_variables)
      screen.diff(expected_json).must_be_nil
    end
  end

  describe "#url" do
    it "shows path" do
      screen.url(111).must_equal "/screen/111"
    end

    it "shows full url" do
      with_env DATADOG_SUBDOMAIN: "foobar" do
        screen.url(111).must_equal "https://foobar.datadoghq.com/screen/111"
      end
    end
  end

  describe ".api_resource" do
    it "is screen" do
      Kennel::Models::Screen.api_resource.must_equal "screen"
    end
  end
end
