# frozen_string_literal: true

require 'rltk/lexer'

module DD
  module MetricFilter
    class Lexer < RLTK::Lexer
      # defaults to matching longest; can choose 'match_first'
      match_first

      r(/\s+/) { :SPACE }
      r(/\(/) { :LPAREN }
      r(/\)/) { :RPAREN }
      r(/:/) { :COLON }
      r(/,/) { :COMMA }
      r(/!/) { :BANG }

      r(/\*/) { :STAR }
      r(/-/) { :DASH }
      r(/\./) { :DOT }
      r(/\//) { :SLASH }

      r(/AND\b/i) { |v| [:AND, v] }
      r(/OR\b/i) { |v| [:OR, v] }
      r(/NOT\b/i) { |v| [:NOT, v] }
      r(/IN\b/i) { |v| [:IN, v] }

      r(/\$(\w+)\.value\b/) { |v| [:TEMPLATE_VARIABLE_DOT_VALUE, v] }
      r(/\$(\w+)/) { |v| [:TEMPLATE_VARIABLE, v] }

      r(/(\w+)/) { |v| [:WORD, v] }
    end
  end
end
