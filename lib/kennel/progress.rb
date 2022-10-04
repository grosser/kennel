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
          Kennel.err.print animation[count % animation.size]
          last_loop = mutex.synchronize {
            stop || cond.wait(mutex, interval)
            stop
          }
          Kennel.err.print "\b"
          break if last_loop
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
