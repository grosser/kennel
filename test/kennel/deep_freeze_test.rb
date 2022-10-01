# frozen_string_literal: true

require_relative "../test_helper"

SingleCov.covered!

describe Kennel::DeepFreeze do
  let(:target) do
    Class.new do
      include Kennel::DeepFreeze
    end.new
  end

  describe "#deep_freeze" do
    it "can freeze strings" do
      input = "foo".dup
      output = target.deep_freeze(input)
      output.must_equal(input)
      output.frozen?.must_equal(true)
      input.frozen?.must_equal(false)
    end

    it "can freeze hashes" do
      input = { ["a"] => "bar".dup }
      input.frozen?.must_equal(false)
      input.keys.first.frozen?.must_equal(false)
      input.values.first.frozen?.must_equal(false)

      output = target.deep_freeze(input)
      output.must_equal(input)

      output.frozen?.must_equal(true)
      output.keys.first.frozen?.must_equal(true)
      output.values.first.frozen?.must_equal(true)

      input.frozen?.must_equal(false)
      input.keys.first.frozen?.must_equal(false)
      input.values.first.frozen?.must_equal(false)
    end

    it "can freeze arrays" do
      input = [["a"], "bar".dup]
      input.frozen?.must_equal(false)
      input[0].frozen?.must_equal(false)
      input[1].frozen?.must_equal(false)

      output = target.deep_freeze(input)
      output.must_equal(input)

      output.frozen?.must_equal(true)
      output[0].frozen?.must_equal(true)
      output[1].frozen?.must_equal(true)

      input.frozen?.must_equal(false)
      input[0].frozen?.must_equal(false)
      input[1].frozen?.must_equal(false)
    end
  end

  describe "#deep_dup_thaw" do
    it "can deeply thaw" do
      input = {
        ["a"].freeze => "b"
      }.freeze

      output = target.deep_dup_thaw(input)

      output.frozen?.must_equal(false)
      output.keys.first.frozen?.must_equal(false)
      output.values.first.frozen?.must_equal(false)
      output.keys.first.first.frozen?.must_equal(false)
    end
  end
end
