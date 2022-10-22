# frozen_string_literal: true

module Kennel
  class OutputLimiter
    def initialize(out, max_lines, &on_overflow)
      @out = out
      @max_lines = max_lines
      @on_overflow = on_overflow
      @seen = 0
    end

    def puts(*content)
      content.join("\n").split("\n").each do |line|
        if @seen >= @max_lines
          @on_overflow&.call
          @on_overflow = nil
          break
        else
          @out.puts(line)
          @seen += 1
        end
      end
    end
  end
end
