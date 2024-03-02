# frozen_string_literal: true

module DD
  module MetricAlertQuery
    require_relative "metric_alert_query/lexer"
    require_relative "metric_alert_query/parser"

    def self.parse(text)
      tokens = MetricAlertQuery::Lexer.lex(text)
      MetricAlertQuery::Parser.parse(tokens)
    end
  end
end
