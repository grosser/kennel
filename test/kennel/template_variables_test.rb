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
    let(:errors) { [] }

    let(:item) do
      item = Object.new
      item.extend Kennel::TemplateVariables
      item.stubs(:invalid!).with { |_tag, err| errors << err }
      item
    end

    def validate(variable_names, widgets)
      data = {
        template_variables: variable_names.map { |v| { name: v } },
        widgets: widgets
      }

      item.send(:validate_json, data)
    end

    it "is valid when empty" do
      validate [], []
      errors.must_be_empty
    end

    it "is valid when vars are empty" do
      validate [], [{ definition: { requests: [{ q: "x" }] } }]
      errors.must_be_empty
    end

    it "is valid when vars are used" do
      validate ["a"], [{ definition: { requests: [{ q: "$a" }] } }]
      errors.must_be_empty
    end

    it "is invalid when vars are not used" do
      validate ["a"], [{ definition: { requests: [{ q: "$b" }] } }]
      errors.length.must_equal 1
    end

    it "is invalid when some vars are not used" do
      validate ["a", "b"], [{ definition: { requests: [{ q: "$b" }] } }]
      errors.length.must_equal 1
    end

    it "is valid when all vars are used" do
      validate ["a", "b"], [{ definition: { requests: [{ q: "$a,$b" }] } }]
    end

    it "is invalid when nested vars are not used" do
      validate ["a"], [{ definition: { widgets: [{ definition: { requests: [{ q: "$b" }] } }] } }]
      errors.length.must_equal 1
    end

    it "works with hostmap widgets" do
      validate ["a"], [{ definition: { requests: { fill: { q: "x" } } } }]
      errors.length.must_equal 1
    end

    it "works with new api format" do
      validate ["a"], [{ definition: { requests: [{ queries: [{ query: "x" }] }] } }]
      errors.length.must_equal 1
    end
  end
end
