# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Progress do
  capture_all

  describe ".progress" do
    it "shows progress" do
      count = 0
      Kennel::Progress.stubs(:sleep).with do
        count += 1
        true
      end
      result = Kennel::Progress.progress("foo") do
        Thread.new { sleep 0.01 until count > 5 }.join
        123
      end
      result.must_equal 123
      stderr.string.must_include "|\b/\b-\b\\\b|\b"
      stderr.string.sub(/-.*?0/, "0").gsub(/\d\.\d+/, "1.11").must_equal "foo ... 1.11s\n"
    end
  end
end
