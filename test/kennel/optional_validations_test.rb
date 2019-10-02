# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::OptionalValidations do
  class TestVariables < Kennel::Models::Base
    include Kennel::OptionalValidations
    settings :project
  end

  it "adds settings" do
    TestVariables.new(validate: -> { false }, project: -> { TestProject.new }).validate.must_equal false
  end

  describe "#validate_json" do
    it "ignores valid" do
      TestVariables.new(project: -> { TestProject.new }).send(:validate_json, a: 1, b: [{ c: 1 }])
    end

    it "shows all valid" do
      e = assert_raises Kennel::Models::Base::ValidationError do
        TestVariables.new(project: -> { TestProject.new }).send(:validate_json, 0 => 1, b: [{ "c" => 1, d: 2 }])
      end
      e.message.must_equal(
        "test_project:test_variables Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
        "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
        "0\n" \
        "\"c\""
      )
    end
  end
end
