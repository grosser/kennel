# frozen_string_literal: true
require_relative "../test_helper"
require "kennel/output_limiter"

SingleCov.covered!

describe Kennel::OutputLimiter do
  it "can show short output" do
    out, _err = capture_io do
      limiter = Kennel::OutputLimiter.new($stdout, 10)
      5.times { |n| limiter.puts n }
    end
    out.must_equal "0\n1\n2\n3\n4\n"
  end

  it "can show up to the limit" do
    out, _err = capture_io do
      limiter = Kennel::OutputLimiter.new($stdout, 5)
      5.times { |n| limiter.puts n }
    end
    out.must_equal "0\n1\n2\n3\n4\n"
  end

  it "stops at the limit (without a block)" do
    out, _err = capture_io do
      limiter = Kennel::OutputLimiter.new($stdout, 3)
      5.times { |n| limiter.puts n }
    end
    out.must_equal "0\n1\n2\n"
  end

  it "stops at the limit (with a block)" do
    times = 0
    callback = -> { times += 1 }
    out, _err = capture_io do
      limiter = Kennel::OutputLimiter.new($stdout, 3, &callback)
      5.times { |n| limiter.puts n }
    end
    out.must_equal "0\n1\n2\n"
    times.must_equal 1
  end
end
