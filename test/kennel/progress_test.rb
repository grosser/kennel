# frozen_string_literal: true
require_relative "../test_helper"

# Hard to cover all the lock cases with certainty.
# `Kennel::Progress.progress("foo") {}` will *probably* cover the last case,
# but there's no guarantee.
SingleCov.covered! uncovered: 1

describe Kennel::Progress do
  capture_all

  describe ".progress" do
    it "shows progress" do
      result = Kennel::Progress.progress("foo", interval: 0.01) do
        sleep 0.1 # make progress print
        123
      end
      result.must_equal 123
      stderr.string.must_include "|\b/\b-\b\\\b|\b"
      stderr.string.sub(/-.*?0/, "0").gsub(/\d\.\d+/, "1.11").must_equal "foo ... 1.11s\n"
    end
  end

  it "stops when worker crashed" do
    assert_raises NotImplementedError do
      Kennel::Progress.progress("foo") do
        sleep 0.01 # make progress print
        raise NotImplementedError
      end
    end
    final = stderr.string
    # p final
    sleep 0.01
    stderr.string.must_equal final, "progress was not stopped"
  end

  it "stops when the block is empty" do
    Kennel::Progress.progress("nothing") {}
  end
end
