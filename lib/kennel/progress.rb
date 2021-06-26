# frozen_string_literal: true
require "benchmark"

module Kennel
  class Progress
    # print what we are doing and a spinner until it is done ... then show how long it took
    def self.progress(name)
      Kennel.err.print "#{name} ... "

      animation = "-\\|/"
      count = 0
      stop = false
      result = nil

      spinner = Thread.new do
        loop do
          break if stop
          Kennel.err.print animation[count % animation.size]
          sleep 0.2
          Kennel.err.print "\b"
          count += 1
        end
      end

      time = Benchmark.realtime { result = yield }

      stop = true
      spinner.join
      Kennel.err.print "#{time.round(2)}s\n"

      result
    ensure
      stop = true
    end
  end
end
