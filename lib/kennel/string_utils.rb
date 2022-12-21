# frozen_string_literal: true
module Kennel
  module StringUtils
    class << self
      def snake_case(string)
        string
          .gsub(/::/, "_") # Foo::Bar -> foo_bar
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # FOOBar -> foo_bar
          .gsub(/([a-z\d])([A-Z])/, '\1_\2') # fooBar -> foo_bar
          .tr("-", "_") # foo-bar -> foo_bar
          .downcase
      end

      # for child projects, not used internally
      def title_case(string)
        string.split(/[\s_]/).map(&:capitalize) * " "
      end

      # simplified version of https://apidock.com/rails/ActiveSupport/Inflector/parameterize
      def parameterize(string)
        string
          .downcase
          .gsub(/[^a-z0-9\-_]+/, "-") # remove unsupported
          .gsub(/-{2,}/, "-") # remove duplicates
          .gsub(/^-|-$/, "") # remove leading/trailing
      end

      def truncate_lines(text, to:, warning:)
        lines = text.split(/\n/, to + 1)
        lines[-1] = warning if lines.size > to
        lines.join("\n")
      end

      def natural_order(name)
        name.split(/(\d+)/).each_with_index.map { |x, i| i.odd? ? x.to_i : x }
      end
    end
  end
end
