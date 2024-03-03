# frozen_string_literal: true

module DD
  module MetricFilter
    require_relative "metric_filter/lexer"
    require_relative "metric_filter/nodes"
    require_relative "metric_filter/parser"

    def self.parse(f)
      tokens = Lexer.lex(f)
      Parser.parse(tokens)
    rescue => e
      { filter_parse_error: e, input: f }
    end
  end
end
