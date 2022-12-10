# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Slo do
  with_test_classes

  class TestSlo < Kennel::Models::Slo
  end

  def slo(options = {})
    Kennel::Models::Slo.new(
      options.delete(:project) || project,
      {
        type: -> { "metric" },
        name: -> { "Foo" },
        kennel_id: -> { "m1" }
      }.merge(options)
    )
  end

  let(:project) { TestProject.new }
  let(:expected_basic_json) do
    {
      name: "Foo\u{1F512}",
      description: nil,
      thresholds: [],
      monitor_ids: [],
      tags: ["service:test_project", "team:test_team"],
      type: "metric"
    }
  end

  describe "#initialize" do
    it "stores project" do
      TestSlo.new(project).project.must_equal project
    end

    it "stores options" do
      TestSlo.new(project, name: -> { "XXX" }).name.must_equal "XXX"
    end
  end

  describe "#as_json" do
    it "creates a basic json" do
      assert_json_equal(
        slo.build!.as_json,
        expected_basic_json
      )
    end

    it "sets query for metrics" do
      expected_basic_json[:query] = "foo"
      assert_json_equal(
        slo(query: -> { "foo" }).build!.as_json,
        expected_basic_json
      )
    end

    it "sets id when updating by id" do
      expected_basic_json[:id] = 123
      assert_json_equal(
        slo(id: -> { 123 }).build!.as_json,
        expected_basic_json
      )
    end

    it "sets groups when given" do
      expected_basic_json[:groups] = ["foo"]
      assert_json_equal(
        slo(groups: -> { ["foo"] }).build!.as_json,
        expected_basic_json
      )
    end
  end

  describe "#validate_json" do
    it "is valid with no thresholds" do
      slo.build!
    end

    it "is valid when warning not set" do
      s = slo(thresholds: [{ critical: 99 }])
      s.build!
    end

    it "is invalid if warning < critical" do
      validation_error_from(slo(thresholds: [{ warning: 0, critical: 99 }]))
        .must_equal "Threshold warning must be greater-than critical value"
    end

    it "is invalid if warning == critical" do
      validation_error_from(slo(thresholds: [{ warning: 99, critical: 99 }]))
        .must_equal "Threshold warning must be greater-than critical value"
    end
  end

  describe ".url" do
    it "shows path" do
      Kennel::Models::Slo.url(111).must_equal "https://app.datadoghq.com/slo?slo_id=111"
    end
  end

  describe ".api_resource" do
    it "is set" do
      Kennel::Models::Slo.api_resource.must_equal "slo"
    end
  end

  describe ".parse_url" do
    it "parses" do
      url = "https://app.datadoghq.com/slo?slo_id=123abc456def123&timeframe=7d&tab=status_and_history"
      Kennel::Models::Slo.parse_url(url).must_equal "123abc456def123"
    end

    it "parses when other query strings are present" do
      url = "https://app.datadoghq.com/slo?query=\"bar\"&slo_id=123abc456def123&timeframe=7d&tab=status_and_history"
      Kennel::Models::Slo.parse_url(url).must_equal "123abc456def123"
    end

    it "parses url with id" do
      url = "https://app.datadoghq.com/slo/edit/123abc456def123"
      Kennel::Models::Slo.parse_url(url).must_equal "123abc456def123"
    end

    it "does not parses url with alert" do
      url = "https://app.datadoghq.com/slo/edit/123abc456def123/alerts/789"
      Kennel::Models::Slo.parse_url(url).must_be_nil
    end

    it "fails to parse other" do
      url = "https://app.datadoghq.com/dashboard/bet-foo-bar?from_ts=1585064592575&to_ts=1585068192575&live=true"
      Kennel::Models::Slo.parse_url(url).must_be_nil
    end
  end

  describe ".normalize" do
    it "works with empty" do
      Kennel::Models::Slo.normalize({ tags: [] }, tags: [])
    end

    it "compares tags sorted" do
      expected = { tags: ["a", "b", "c"] }
      actual = { tags: ["b", "c", "a"] }
      Kennel::Models::Slo.normalize(expected, actual)
      expected.must_equal tags: ["a", "b", "c"]
      actual.must_equal tags: ["a", "b", "c"]
    end

    it "ignores defaults" do
      expected = { tags: [] }
      actual = { monitor_ids: [], tags: [] }
      Kennel::Models::Slo.normalize(expected, actual)
      expected.must_equal(tags: [])
      actual.must_equal(tags: [])
    end

    it "ignores readonly display values" do
      expected = { thresholds: [{ warning: 1.0 }], tags: [] }
      actual = { thresholds: [{ warning: 1.0, warning_display: "1.00" }], tags: [] }
      Kennel::Models::Slo.normalize(expected, actual)
      expected.must_equal(thresholds: [{ warning: 1.0 }], tags: [])
      actual.must_equal expected
    end
  end
end
