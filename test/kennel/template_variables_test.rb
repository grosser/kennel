# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::TemplateVariables do
  define_test_classes

  it "adds settings" do
    Kennel::Models::Dashboard.new(TestProject.new, kennel_id: -> { "test" }, template_variables: -> { ["xxx"] }).template_variables.must_equal ["xxx"]
  end

  describe "#render_template_variables" do
    def var(value)
      Kennel::Models::Dashboard.new(TestProject.new, kennel_id: -> { "test" }, template_variables: -> { value }).send(:render_template_variables)
    end

    it "leaves empty alone" do
      var([]).must_equal []
    end

    it "expands simple" do
      var(["xxx"]).must_equal [{ default: "*", prefix: "xxx", name: "xxx" }]
    end

    it "leaves complicated" do
      var([{ foo: "bar" }]).must_equal [{ foo: "bar" }]
    end
  end

  describe "#validate_json" do
    let(:errors) { item.validation_errors }
    let(:error_tags) { errors.map(&:tag) }
    let(:item) { Kennel::Models::Dashboard.new(TestProject.new) }

    def validate(variable_names, widgets)
      data = {
        tags: [],
        template_variables: variable_names.map { |v| { name: v } },
        widgets: widgets
      }
      item.send(:validate_json, data)
    end

    it "is valid when empty" do
      validate [], []
      error_tags.must_equal []
    end

    it "is valid when vars are empty" do
      validate [], [{ definition: { requests: [{ q: "x" }] } }]
      error_tags.must_equal []
    end

    it "is valid when vars are used" do
      validate ["a"], [{ definition: { requests: [{ q: "$a" }] } }]
      error_tags.must_equal []
    end

    it "is invalid when vars are not used" do
      validate ["a"], [{ definition: { requests: [{ q: "$b" }] } }]
      error_tags.must_equal [:queries_must_use_template_variables]
    end

    it "is invalid when some vars are not used" do
      validate ["a", "b"], [{ definition: { requests: [{ q: "$b" }] } }]
      error_tags.must_equal [:queries_must_use_template_variables]
    end

    it "is valid when all vars are used" do
      validate ["a", "b"], [{ definition: { requests: [{ q: "$a,$b" }] } }]
      error_tags.must_equal []
    end

    it "is invalid when nested vars are not used" do
      validate ["a"], [{ definition: { widgets: [{ definition: { requests: [{ q: "$b" }] } }] } }]
      error_tags.must_equal [:queries_must_use_template_variables]
    end

    it "works with hostmap widgets" do
      validate ["a"], [{ definition: { requests: { fill: { q: "x" } } } }]
      error_tags.must_equal [:queries_must_use_template_variables]
    end

    it "works with new api format" do
      validate ["a"], [{ definition: { requests: [{ queries: [{ query: "x" }] }] } }]
      error_tags.must_equal [:queries_must_use_template_variables]
    end

    it "still calls existing validations" do
      validate [], [{ "definition" => { requests: [{ q: "x" }] } }]
      error_tags.must_equal [:unignorable]
    end
  end
end
