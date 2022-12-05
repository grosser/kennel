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
    item.define_singleton_method(:invalid!) do |_tag, err|
      copy_of_errors << err
    end
    item
  end

  it "adds settings" do
    record = Kennel::Models::Record.new(TestProject.new, kennel_id: -> { "test" }, ignored_errors: -> { [:foo] })
    record.ignored_errors.must_equal [:foo]
  end

  describe ".valid?" do
    capture_all

    def good
      part = mock
      part.stubs(:filtered_validation_errors).returns([])
      part
    end

    def bad(id, errors)
      part = mock
      part.stubs(:safe_tracking_id).returns(id)
      part.stubs(:filtered_validation_errors).returns(errors)
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

    context "with errors" do
      it "runs with a bad part" do
        parts = [
          bad(
            "foo",
            [
              Kennel::OptionalValidations::ValidationMessage.new(:data, "your data is bad"),
              Kennel::OptionalValidations::ValidationMessage.new(:you, "and you should feel bad")
            ]
          )
        ]
        refute Kennel::OptionalValidations.valid?(parts)
        stdout.string.must_equal ""
        stderr.string.must_equal <<~TEXT

          foo [:data] your data is bad
          foo [:you] and you should feel bad

          If a particular error cannot be fixed, it can be marked as ignored via `ignored_errors`, e.g.:
            Kennel::Models::Monitor.new(
              ...,
              ignored_errors: [:you]
            )

        TEXT
      end

      it "uses the last non-ignorable tag as the example" do
        parts = [
          bad(
            "foo",
            [
              Kennel::OptionalValidations::ValidationMessage.new(:data, "your data is bad"),
              Kennel::OptionalValidations::ValidationMessage.new(:unignorable, "and you should feel bad")
            ]
          )
        ]

        refute Kennel::OptionalValidations.valid?(parts)

        stderr.string.must_include "foo [:unignorable] and you should feel bad"
        stderr.string.must_include "ignored_errors: [:data]"
      end

      it "skips the ignored_errors advice is all the errors are unignorable" do
        parts = [
          bad(
            "foo",
            [
              Kennel::OptionalValidations::ValidationMessage.new(:unignorable, "your data is bad"),
              Kennel::OptionalValidations::ValidationMessage.new(:unignorable, "and you should feel bad")
            ]
          )
        ]

        refute Kennel::OptionalValidations.valid?(parts)

        refute_includes stderr.string, "If a particular error cannot be fixed"
      end
    end
  end

  describe "filter_validation_errors" do
    let(:ignored_errors) { [] }

    let(:item) do
      Kennel::Models::Record.new(TestProject.new, kennel_id: -> { "test" }, ignored_errors: ignored_errors)
    end

    context "no validation errors" do
      it "passes if ignored_errors is empty" do
        item.build
        item.filtered_validation_errors.must_be_empty
      end

      it "fails if ignored_errors is not empty" do
        ignored_errors << :foo
        item.build
        errs = item.filtered_validation_errors
        errs.length.must_equal 1
        errs[0].tag.must_equal :unignorable
        errs[0].text.must_include "there are no errors to ignore"
      end
    end

    context "some validation errors" do
      with_env(NO_IGNORED_ERRORS: nil)

      before do
        item.define_singleton_method(:validate_json) do |_json|
          invalid! :x, "Bad juju"
          invalid! :y, "Worse juju"
        end
      end

      it "does not ignore the error" do
        item.build
        errs = item.filtered_validation_errors
        errs.length.must_equal 2
        errs[0].tag.must_equal :x
        errs[1].tag.must_equal :y
      end

      it "can ignore the error" do
        ignored_errors << :x
        ignored_errors << :y
        item.build
        item.filtered_validation_errors.must_be_empty
      end

      it "cannot ignore unignorable errors" do
        item.define_singleton_method(:validate_json) do |_json|
          invalid! :unignorable, "This is serious"
        end

        ignored_errors << :unignorable

        item.build
        errs = item.filtered_validation_errors
        errs.length.must_equal 1
        errs[0].tag.must_equal :unignorable
      end

      it "still reports non-ignored errors" do
        ignored_errors << :x
        item.build
        errs = item.filtered_validation_errors
        errs.length.must_equal 1
        errs[0].tag.must_equal :y
      end

      it "complains if an ignored error didn't happen" do
        ignored_errors << :x
        ignored_errors << :y
        ignored_errors << :zzz
        item.build
        errs = item.filtered_validation_errors
        errs.length.must_equal 1
        errs[0].tag.must_equal :unignorable
        errs[0].text.must_include ":zzz"
      end

      it "reports ignored errors if NO_IGNORED_ERRORS is set" do
        with_env(NO_IGNORED_ERRORS: "any value") do
          ignored_errors << :x
          ignored_errors << :y
          item.build
          errs = item.filtered_validation_errors
          errs.length.must_equal 2
          errs[0].tag.must_equal :x
          errs[1].tag.must_equal :y
        end
      end
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
