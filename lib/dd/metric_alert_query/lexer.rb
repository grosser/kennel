# frozen_string_literal: true

require 'rltk/lexer'

module DD
  module MetricAlertQuery
    class Lexer < RLTK::Lexer

      r(/(\w+):([A-Za-z0-9._-]+)\{(.*?)\}/) do |agg, name, filter|
        [:AGG_NAME_FILTER, { agg:, name:, filter: }]
      end

      r(/\s+by\s+\{.*?\}/) do |by|
        [:BY, { by: }]
      end

      r(/\s+([<>]=?)\s+([0-9.]+)\s*$/) do |operator, threshold|
        [:COMPARISON, { operator:, threshold: }]
      end

      r(/(avg|sum|min|max|percentile)\(last_\d+\w\)/) do |aggregate, time|
        [:AGG_TIME, { aggregate:, time: } ]
      end

      r(/\.(as_count|as_rate)\(\)/) { |f| [:AS_RATE_OR_COUNT, f] }
      r(/default_zero\b/) { :DEFAULT_ZERO }
      r(/derivative\b/) { :DERIVATIVE }

      r(/\s+/) { :SPACE }
      r(/([+-]?(?:\d+(?:\.\d+)?|\.\d+))/) { |t| [:NUMBER, t] }
      r(/:/) { :COLON }
      r(/\(/) { :LPAREN }
      r(/\)/) { :RPAREN }
      r(/[*\/+-]/) { |t| [:BINOP, t] }

      # r(/(avg|sum)\b/) { |t| [:AGG, t] }
      # r(/last_\d+\w\b/) { |t| [:LAST, t] }
      #
      # r(/[a-z]\w+(\.\w+)+/) { |t| [:DOT_CHAIN, t] }
      # r(/\{/) { :LBRACE }
      # r(/\}/) { :RBRACE }
      # r(/\w+([.-]\w+)*/) { |t| [:DASHABLE_WORD, t] }
      # r(/,/) { :COMMA }
      # r(/by\b/) { :BY }
      # # r(/[<>]=?/) { :LTGT }
    end
  end
end
