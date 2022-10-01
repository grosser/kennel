# frozen_string_literal: true
require "benchmark"

module Kennel
  class Progress
    # print what we are doing and a spinner until it is done ... then show how long it took
    def self.progress(name, interval: 0.2)
      Kennel.err.print "#{name} ... "

      mutex = Mutex.new
      cond = ConditionVariable.new
      stop = false
      result = nil

      spinner = Thread.new do
        animation = "-\\|/"
        count = 0
        loop do
          break if mutex.synchronize { stop }
          Kennel.err.print animation[count % animation.size]
          mutex.synchronize do
            cond.wait(mutex, interval)
          end
          Kennel.err.print "\b"
          count += 1
        end
      end

      time = Benchmark.realtime { result = yield }

      mutex.synchronize do
        stop = true
        cond.broadcast
      end

      spinner.join

      Kennel.err.print "#{time.round(2)}s\n"

      result
    ensure
      mutex.synchronize do
        stop = true
        cond.broadcast
      end
    end
  end
end
