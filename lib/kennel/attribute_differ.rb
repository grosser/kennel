# frozen_string_literal: true

require "diff/lcs"

module Kennel
  class AttributeDiffer
    def initialize
      # min '2' because: -1 makes no sense, 0 does not work with * 2 math, 1 says '1 lines'
      @max_diff_lines = [Integer(ENV.fetch("MAX_DIFF_LINES", "50")), 2].max
      super
    end

    def format(type, field, old, new = nil)
      multiline = false
      if type == "+"
        temp = pretty_inspect(new)
        new = pretty_inspect(old)
        old = temp
      elsif old.is_a?(String) && new.is_a?(String) && (old.include?("\n") || new.include?("\n"))
        multiline = true
      else # ~ and -
        old = pretty_inspect(old)
        new = pretty_inspect(new)
      end

      message =
        if multiline
          "  #{type}#{field}\n" +
            multiline_diff(old, new).map { |l| "    #{l}" }.join("\n")
        elsif (old + new).size > 100
          "  #{type}#{field}\n" \
          "    #{old} ->\n" \
          "    #{new}"
        else
          "  #{type}#{field} #{old} -> #{new}"
        end

      truncate(message)
    end

    private

    # display diff for multi-line strings
    # must stay readable when color is off too
    def multiline_diff(old, new)
      Diff::LCS.sdiff(old.split("\n", -1), new.split("\n", -1)).flat_map do |diff|
        case diff.action
        when "-"
          Utils.color(:red, "- #{diff.old_element}")
        when "+"
          Utils.color(:green, "+ #{diff.new_element}")
        when "!"
          [
            Utils.color(:red, "- #{diff.old_element}"),
            Utils.color(:green, "+ #{diff.new_element}")
          ]
        else
          "  #{diff.old_element}"
        end
      end
    end

    def truncate(message)
      warning = Utils.color(
        :magenta,
        "  (Diff for this item truncated after #{@max_diff_lines} lines. " \
        "Rerun with MAX_DIFF_LINES=#{@max_diff_lines * 2} to see more)"
      )
      StringUtils.truncate_lines(message, to: @max_diff_lines, warning: warning)
    end

    # TODO: use awesome-print or similar, but it has too many monkey-patches
    # https://github.com/amazing-print/amazing_print/issues/36
    def pretty_inspect(object)
      string = object.inspect.dup
      string.gsub!(/:([a-z_]+)=>/, "\\1: ")
      10.times do
        string.gsub!(/{(\S.*?\S)}/, "{ \\1 }") || break
      end
      string
    end
  end
end
