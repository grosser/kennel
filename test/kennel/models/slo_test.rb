# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Slo do
  class TestSlo < Kennel::Models::Slo
  end

  # generate readables diffs when things are not equal
  def assert_json_equal(a, b)
    JSON.pretty_generate(a).must_equal JSON.pretty_generate(b)
  end

  def slo(options = {})
    Kennel::Models::Slo.new(
      options.delete(:project) || project,
      {
        type: -> { "metric" },
        name: -> { "Foo" },
        kennel_id: -> { "m1" },
        thresholds: -> { [] }
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

    describe "validates threshold" do
      it "is valid when warning not set" do
        Kennel::Models::Slo.new(project, thresholds: -> { [{ critical: 99 }] })
      end

      it "is invalid if warning > critical" do
        assert_raises Kennel::ValidationError do
          Kennel::Models::Slo.new(project, thresholds: -> { [{ warning: 0, critical: 99 }] })
        end
      end

      it "is invalid if warning == critical" do
        assert_raises Kennel::ValidationError do
          Kennel::Models::Slo.new(project, thresholds: -> { [{ warning: 99, critical: 99 }] })
        end
      end
    end
  end

  describe "#as_json" do
    it "creates a basic json" do
      assert_json_equal(
        slo.as_json,
        expected_basic_json
      )
    end

    it "sets query for metrics" do
      expected_basic_json[:query] = "foo"
      assert_json_equal(
        slo(query: -> { "foo" }).as_json,
        expected_basic_json
      )
    end

    it "sets id when updating by id" do
      expected_basic_json[:id] = 123
      assert_json_equal(
        slo(id: -> { 123 }).as_json,
        expected_basic_json
      )
    end

    it "sets groups when given" do
      expected_basic_json[:groups] = ["foo"]
      assert_json_equal(
        slo(groups: -> { ["foo"] }).as_json,
        expected_basic_json
      )
    end
  end

  describe "#resolve_linked_tracking_ids" do
    it "does nothing for hardcoded ids" do
      slo = slo(monitor_ids: -> { [123] })
      slo.resolve_linked_tracking_ids({})
      slo.as_json[:monitor_ids].must_equal [123]
    end

    it "resolves relative ids" do
      slo = slo(monitor_ids: -> { ["#{project.kennel_id}:mon"] })
      slo.resolve_linked_tracking_ids("#{project.kennel_id}:mon" => 123)
      slo.as_json[:monitor_ids].must_equal [123]
    end

    it "allows unresolvable ids so monitors can be created with slos" do
      slo = slo(monitor_ids: -> { ["#{project.kennel_id}:mon"] })
      Kennel.err.expects(:puts)
      slo.resolve_linked_tracking_ids("#{project.kennel_id}:mon" => :new)
      slo.as_json[:monitor_ids].must_equal [1]
    end

    it "fails with typos" do
      slo = slo(monitor_ids: -> { ["#{project.kennel_id}:mon"] })
      assert_raises Kennel::ValidationError do
        slo.resolve_linked_tracking_ids({})
      end
    end
  end

  describe "#url" do
    it "shows path" do
      slo.url(111).must_equal "/slo?slo_id=111"
    end
  end

  describe ".api_resource" do
    it "is set" do
      Kennel::Models::Slo.api_resource.must_equal "slo"
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
