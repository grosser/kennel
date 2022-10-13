# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Progress do
  capture_all

  describe ".progress" do
    it "shows progress (with tty)" do
      Kennel.err.stubs(:tty?).returns(true)
      result = Kennel::Progress.progress("foo", interval: 0.01) do
        sleep 0.10 # make progress print multiple times
        123
      end
      result.must_equal 123
      stderr.string.must_include "|\b/\b-\b\\\b|\b"
      stderr.string.sub(/-.*?0/, "0").gsub(/\d\.\d+/, "1.11").must_equal "foo ... 1.11s\n"
    end

    it "shows progress (without tty)" do
      Kennel.err.stubs(:tty?).returns(false)
      result = Kennel::Progress.progress("foo", interval: 0.01) do
        sleep 0.10 # if there were a tty, this would make it print the spinner
        123
      end
      result.must_equal 123
      stderr.string.sub(/-.*?0/, "0").gsub(/\d\.\d+/, "1.11").must_equal "foo ...\nfoo ... 1.11s\n"
    end

    it "stops immediately when block finishes" do
      Benchmark.realtime do
        Kennel::Progress.progress("foo", interval: 1) do
          sleep 0.01 # make it do at least 1 loop
          123
        end.must_equal 123
      end.must_be :<, 0.1
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
end
