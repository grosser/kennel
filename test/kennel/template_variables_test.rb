# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::TemplateVariables do
  class TestVariables < Kennel::Models::Base
    include Kennel::TemplateVariables
  end

  it "adds settings" do
    TestVariables.new(template_variables: -> { ["xxx"] }).template_variables.must_equal ["xxx"]
  end

  describe "#render_template_variables" do
    def var(value)
      TestVariables.new(template_variables: -> { value }).send(:render_template_variables)
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
end
