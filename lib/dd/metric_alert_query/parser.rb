# frozen_string_literal: true

require 'rltk/parser'

module DD
  module MetricAlertQuery
    class Parser < RLTK::Parser
      start :mq

      # production(:mq, 'COLON') { |_| nil }
      production(:mq, '.AGG_TIME COLON .expression .COMPARISON') do |a, e, c|
        [:mq, { a:, e:, c: } ]
      end

      production(:anfb, 'AGG_NAME_FILTER BY? AS_RATE_OR_COUNT?') do |anf, by, rate_or_count|
        [:anfb, { anf:, by:, rate_or_count: } ]
      end

      production(:expression) do
        clause('SPACE .expression') { |e| e }
        clause('NUMBER') { |e| e }
        clause('LPAREN SPACE? .expression SPACE? RPAREN') { |e| e }
        clause('DEFAULT_ZERO LPAREN .expression RPAREN') { |e| [:default_zero, e] }
        clause('DERIVATIVE LPAREN .expression RPAREN') { |e| [:derivative, e] }
        clause('.anfb') { |m| [:expr, m] }

        clause('.expression .BINOP .expression') { |a, op, b| [:binop, { a:, op:, b: } ] }
      end

      # production(:agg_window, '.AGG LPAREN .LAST RPAREN') do |agg, last|
      #   [:win, { agg:, last: } ]
      # end
      #
      # production(:expression) do
      #   clause('.metric_expression') { |m| m }
      # end
      #
      # production(:metric_expression, '.AGG COLON .DOT_CHAIN LBRACE')

      finalize
    end
  end
end
