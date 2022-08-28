# frozen_string_literal: true
require "benchmark"

module Kennel
  class Progress
    # print what we are doing and a spinner until it is done ... then show how long it took
    def self.progress(name)
      Kennel.err.print "#{name} ... "

      stop = false
      result = nil
      mutex = Mutex.new

      spinner = Thread.new do
        animation = "-\\|/"
        count = 0
        loop do
          break if mutex.synchronize { stop }
          Kennel.err.print animation[count]
          sleep 0.2
          Kennel.err.print "\b"
          count = (count + 1) % animation.size
        end
      end

      time = Benchmark.realtime { result = yield }

      mutex.synchronize { stop = true }
      spinner.join
      Kennel.err.print "#{time.round(2)}s\n"

      result
    ensure
      stop = true
    end
  end
end
