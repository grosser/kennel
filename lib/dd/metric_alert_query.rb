# frozen_string_literal: true

module DD
  module MetricAlertQuery
    require_relative "metric_alert_query/lexer"
    require_relative "metric_alert_query/parser"

    def self.parse(text)
      tokens = MetricAlertQuery::Lexer.lex(text)
      MetricAlertQuery::Parser.parse(tokens)
    end

    def self.lazy_parse(q)
      match = q.match(/^(?<aggregate>.*?):(?<expression>.*)(?<comparator>[<>]=?|==)\s*(?<threshold>[+-]?[0-9\.]+)\s*$/sm)

      if match.nil?
        raise "Fails basic structure"
      end

      aggregate = match["aggregate"]
      expression = match["expression"]
      comparator = match["comparator"]
      threshold = match["threshold"].to_f

      by_pod_fragments = {}
      expression.gsub!(/\}\s+by\s+\{(.*?)\}/) do
        key = "BY-CLAUSE-%03d" % [by_pod_fragments.size]
        by_pod_fragments[key] = $1.strip.split(/\s*,\s*/)
        "} #{key}"
      end

      filter_fragments = {}
      expression.gsub!(/\{([^}]+)}/) do
        key = "FILTER-CLAUSE-%03d" % [filter_fragments.size]
        filter_fragments[key] = $1.strip
        " #{key} "
      end

      filter_fragments.transform_values! do |f|
        DD::MetricFilter.parse(f)
      end

      {
        aggregate:,
        expression:,
        comparator:,
        threshold:,
        by_pod_fragments:,
        filter_fragments:
      }
    end
  end
end
