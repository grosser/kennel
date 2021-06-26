# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Progress do
  capture_all

  before { Kennel::Progress.stubs(:sleep) } # make things fast

  describe ".progress" do
    it "shows progress" do
      result = Kennel::Progress.progress("foo") do
        sleep 0.01 # make progress print
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
end
