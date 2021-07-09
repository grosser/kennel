# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::SyntheticTest do
  class TestSynth < Kennel::Models::SyntheticTest
  end

  def synthetic(options = {})
    Kennel::Models::SyntheticTest.new(
      options.delete(:project) || project,
      {
        kennel_id: -> { "m1" },
        locations: -> { ["l1"] },
        message: -> { "hey" },
        config: -> { {} },
        type: -> { "api" },
        subtype: -> { "http" },
        options: -> { {} },
        name: -> { "foo" }
      }.merge(options)
    )
  end

  let(:project) { TestProject.new }
  let(:expected_json) do
    {
      message: "hey",
      tags: [
        "service:test_project",
        "team:test_team"
      ],
      config: {},
      type: "api",
      subtype: "http",
      options: {},
      name: "foo",
      locations: ["l1"]
    }
  end

  describe "#as_json" do
    it "builds" do
      assert_json_equal synthetic.as_json, expected_json
    end

    it "caches" do
      s = synthetic
      s.expects(:locations)
      2.times { s.as_json }
    end

    it "can add id" do
      synthetic(id: -> { 123 }).as_json[:id].must_equal 123
    end

    it "can add all locations" do
      synthetic(locations: -> { :all }).as_json[:locations].size.must_be :>, 5
    end

    it "can use super" do
      synthetic(message: -> { super() }).as_json[:message].must_equal "\n\n@slack-foo"
    end
  end

  describe ".api_resource" do
    it "is set" do
      Kennel::Models::SyntheticTest.api_resource.must_equal "synthetics/tests"
    end
  end

  describe ".url" do
    it "builds" do
      Kennel::Models::SyntheticTest.url("foo").must_equal "/synthetics/details/foo"
    end
  end

  describe ".parse_url" do
    it "extracts" do
      Kennel::Models::SyntheticTest.parse_url("https://foo.com/synthetics/details/foo-bar-baz").must_equal "foo-bar-baz"
    end
  end

  describe ".normalize" do
    it "sorts tags" do
      a = { tags: ["a", "b"] }
      e = { tags: ["b", "a"] }
      Kennel::Models::SyntheticTest.normalize(a, e)
      e[:tags].must_equal ["a", "b"]
    end
  end
end
