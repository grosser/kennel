# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::OptionalValidations do
  define_test_classes

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
      part.stubs(:validation_errors).returns([])
      part.stubs(:ignored_errors).returns([])
      part
    end

    def bad(id, errors)
      part = mock
      part.stubs(:safe_tracking_id).returns(id)
      part.stubs(:validation_errors).returns(errors)
      part.stubs(:ignored_errors).returns([])
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

  describe ".filter_validation_errors" do
    let(:ignored_errors) { [] }

    let(:item) do
      Kennel::Models::Record.new(TestProject.new, kennel_id: -> { "test" }, ignored_errors: ignored_errors)
    end

    context "no validation errors" do
      it "passes if ignored_errors is empty" do
        item.build
        Kennel::OptionalValidations.send(:filter_validation_errors, item).must_equal []
      end

      context "when ignored_errors is not empty" do
        before { ignored_errors << :foo }

        it "fails" do
          item.build
          errs = Kennel::OptionalValidations.send(:filter_validation_errors, item)
          errs.length.must_equal 1
          errs[0].tag.must_equal :unused_ignores
          errs[0].text.must_include "there are no errors to ignore"
        end

        it "can ignore failures" do
          ignored_errors << :unused_ignores
          item.build
          item.filtered_validation_errors.must_equal []
        end
      end
    end

    context "some validation errors" do
      before do
        item.define_singleton_method(:validate_json) do |_json|
          invalid! :x, "Bad juju"
          invalid! :y, "Worse juju"
        end
      end

      it "shows the error" do
        item.build
        errs = Kennel::OptionalValidations.send(:filter_validation_errors, item)
        errs.length.must_equal 2
        errs[0].tag.must_equal :x
        errs[1].tag.must_equal :y
      end

      it "can ignore errors" do
        ignored_errors << :x
        ignored_errors << :y
        item.build
        Kennel::OptionalValidations.send(:filter_validation_errors, item).must_equal []
      end

      it "cannot ignore unignorable errors" do
        item.define_singleton_method(:validate_json) do |_json|
          invalid! :unignorable, "This is serious"
        end

        ignored_errors << :unignorable

        item.build
        errs = Kennel::OptionalValidations.send(:filter_validation_errors, item)
        errs.length.must_equal 1
        errs[0].tag.must_equal :unignorable
      end

      it "reports non-ignored errors" do
        ignored_errors << :x
        item.build
        errs = Kennel::OptionalValidations.send(:filter_validation_errors, item)
        errs.length.must_equal 1
        errs[0].tag.must_equal :y
      end

      context "when an ignored error didn't happen" do
        before do
          ignored_errors << :x
          ignored_errors << :y
          ignored_errors << :zzz
        end

        it "complains" do
          item.build
          errs = Kennel::OptionalValidations.send(:filter_validation_errors, item)
          errs.length.must_equal 1
          errs[0].tag.must_equal :unused_ignores
          errs[0].text.must_include ":zzz"
        end

        it "does not complain if that was ignored" do
          ignored_errors << :unused_ignores
          item.build
          item.filtered_validation_errors.must_equal []
        end
      end

      it "reports ignored errors if NO_IGNORED_ERRORS is set" do
        with_env(NO_IGNORED_ERRORS: "any value") do
          ignored_errors << :x
          ignored_errors << :y
          item.build
          errs = Kennel::OptionalValidations.send(:filter_validation_errors, item)
          errs.length.must_equal 2
          errs[0].tag.must_equal :x
          errs[1].tag.must_equal :y
        end
      end
    end
  end
end
