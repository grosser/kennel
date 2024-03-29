# frozen_string_literal: true
require "benchmark"

module Kennel
  class Progress
    # print what we are doing and a spinner until it is done ... then show how long it took
    def self.progress(name, interval: 0.2, plain: false, &block)
      return progress_no_tty(name, &block) if plain || !Kennel.err.tty?

      Kennel.err.print "#{name} ... "

      stop = false
      result = nil

      spinner = Thread.new do
        animation = "-\\|/"
        count = 0
        loop do
          break if stop
          Kennel.err.print animation[count % animation.size]
          sleep interval
          Kennel.err.print "\b"
          count += 1
        end
      end

      time = Benchmark.realtime { result = block.call }

      stop = true
      begin
        spinner.run # wake thread, so it stops itself
      rescue ThreadError
        # thread was already dead, but we can't check with .alive? since it's a race condition
      end
      spinner.join
      Kennel.err.print "#{time.round(2)}s\n"

      result
    ensure
      stop = true # make thread stop without killing it
    end

    class << self
      private

      def progress_no_tty(name)
        Kennel.err.puts "#{name} ..."
        result = nil
        time = Benchmark.realtime { result = yield }
        Kennel.err.puts "#{name} ... #{time.round(2)}s"
        result
      end
    end
  end
end
