# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::OptionalValidations do
  with_test_classes

  let(:errors) { [] }

  let(:item) do
    item = Object.new
    item.extend Kennel::OptionalValidations
    copy_of_errors = errors
    item.define_singleton_method(:invalid!) do |err|
      copy_of_errors << err
    end
    item
  end

  it "adds settings" do
    Kennel::Models::Dashboard.new(TestProject.new, kennel_id: -> { "test" }, validate: -> { false }).validate.must_equal false
  end

  describe ".valid?" do
    capture_all

    def good
      part = mock
      part.stubs(:unfiltered_validation_errors).returns([])
      part
    end

    def bad(id, errors)
      part = mock
      part.stubs(:safe_tracking_id).returns(id)
      part.stubs(:unfiltered_validation_errors).returns(errors)
      part
    end

    it "runs with no parts" do
      assert(Kennel::OptionalValidations.valid?([]))
      stdout.string.must_equal ""
      stderr.string.must_equal ""
    end

    it "runs with only good parts" do
      assert(Kennel::OptionalValidations.valid?([good, good, good]))
      stdout.string.must_equal ""
      stderr.string.must_equal ""
    end

    it "runs with a bad part" do
      refute(
        Kennel::OptionalValidations.valid?(
          [
            bad("foo", ["your data is bad", "and you should feel bad"])
          ]
        )
      )
      stdout.string.must_equal ""
      stderr.string.must_equal <<~TEXT

        foo your data is bad
        foo and you should feel bad

      TEXT
    end
  end

  describe "#validate_json" do
    def expect_error(bad)
      errors.length.must_equal 1
      errors[0].must_match(/Only use Symbols as hash keys/)
      errors[0].must_match(/'foo' => 1 --> 'foo': 1/)
      found = errors[0].scan(/^"(.*?)"$/m).flatten
      found.must_equal(bad)
    end

    it "passes on symbols" do
      item.send(:validate_json, { some_key: "bar" })
      errors.must_be_empty
    end

    it "fails on strings" do
      item.send(:validate_json, { "some_key" => "bar" })
      expect_error(["some_key"])
    end

    it "checks inside hashes" do
      item.send(:validate_json, { outer: { "some_key" => "bar" } })
      expect_error(["some_key"])
    end

    it "checks inside arrays" do
      item.send(:validate_json, { outer: [{ "some_key" => "bar" }] })
      expect_error(["some_key"])
    end

    it "reports all bad keys" do
      data = {
        "bad_y" => 1,
        :good => {
          "bad_x" => 1,
          :good_z => { "bad_y" => 0 }
        }
      }
      item.send(:validate_json, data)
      expect_error(["bad_x", "bad_y"])
    end
  end
end
