# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::OptionalValidations do
  with_test_classes

  it "adds settings" do
    Kennel::Models::Dashboard.new(TestProject.new, kennel_id: -> { "test" }, validate: -> { false }).validate.must_equal false
  end

  describe "#validate_json" do
    it "ignores valid" do
      Kennel::Models::Dashboard.new(TestProject.new, kennel_id: -> { "test" }).send(:validate_json, a: 1, b: [{ c: 1 }])
    end

    it "shows all valid" do
      e = assert_raises Kennel::ValidationError do
        Kennel::Models::Dashboard.new(TestProject.new, kennel_id: -> { "test" }).send(:validate_json, 0 => 1, b: [{ "c" => 1, d: 2 }])
      end
      e.tag.must_equal :hash_keys_must_be_symbols
      e.base_message.must_equal(
        "Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
        "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
        "0\n" \
        "\"c\""
      )
    end
  end
end
