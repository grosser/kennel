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

  describe ".all_keys" do
    it "finds keys for hash" do
      Kennel::OptionalValidations.all_keys(foo: 1).must_equal [:foo]
    end

    it "finds keys for hash in array" do
      Kennel::OptionalValidations.all_keys([{ foo: 1 }]).must_equal [:foo]
    end

    it "finds keys for multiple" do
      Kennel::OptionalValidations.all_keys([{ foo: 1 }, [[[{ bar: 2 }]]]]).must_equal [:foo, :bar]
    end
  end

  describe "#validate_json" do
    it "ignores valid" do
      TestVariables.new(project: -> { TestProject.new }).send(:validate_json, a: 1, b: [{ c: 1 }])
    end

    it "shows all valid" do
      e = assert_raises Kennel::Models::Base::ValidationError do
        TestVariables.new(project: -> { TestProject.new }).send(:validate_json, 0 => 1, b: [{ "c" => 1, d: 2 }])
      end
      e.message.must_equal "test_project:test_variables only use Symbols to avoid permanent diffs (0, \"c\")"
    end
  end
end
