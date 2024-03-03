# frozen_string_literal: true

require 'rltk/parser'

module DD
  module MetricFilter
    class Parser < RLTK::Parser
      include Nodes

      start :expression

      production(:expression) do
        clause('.simple_expression') { |x| x }
        clause('.simple_expression SPACE? COMMA .expression') do |a, b|
          b.is_a?(CommaList) ? CommaList.new([a, *b.items]) : CommaList.new([a, b])
        end
        clause('.simple_expression SPACE AND SPACE .expression') do |a, b|
          b.is_a?(AndList) ? AndList.new([a, *b.items]) : AndList.new([a, b])
        end
        clause('.simple_expression SPACE OR SPACE .expression') do |a, b|
          b.is_a?(OrList) ? OrList.new([a, *b.items]) : OrList.new([a, b])
        end
      end

      production(:simple_expression) do
        clause('SPACE .simple_expression') { |v| v }
        clause('LPAREN .SPACE? expression SPACE? RPAREN') { |e| e }

        clause('NOT SPACE .simple_expression') { |e| Not.new(e) }
        clause('BANG .simple_expression') { |e| Bang.new(e) }

        clause('TEMPLATE_VARIABLE') { |v| TemplateVariable.new(v) }
        clause('.key COLON .value') { |k, v| KeyValuePair.new(k, v) }
        clause('.key SPACE IN SPACE? LPAREN SPACE? .in_list SPACE? RPAREN') { |k, v| InClause.new(k, v) }
        clause('.key SPACE NOT SPACE IN SPACE? LPAREN SPACE? .in_list SPACE? RPAREN') { |k, v| Not.new(InClause.new(k, v)) }
        clause('.key') { |k| KeyOnly.new(k) }

        clause('STAR') { |k| Star.new }
      end

      # String
      production(:key) do
        clause('.WORD DASH .key') { |a, b| "#{a}-#{b}" }
        clause('.WORD SLASH .key') { |a, b| "#{a}/#{b}" }
        clause('.WORD DOT .key') { |a, b| "#{a}.#{b}" }
        clause('WORD') { |v| v }
      end

      production(:value) do
        clause('TEMPLATE_VARIABLE_DOT_VALUE') { |v| TemplateValue.new(v) }
        clause('simple_value') { |v| SimpleValue.new(v) }
      end

      # String
      production(:simple_value) do
        clause('value_part simple_value') { |a, b| a + b }
        clause('value_part') { |v| v }
      end

      # String
      production(:value_part) do
        clause('WORD') { |v| v }
        clause('STAR') { |v| '*' }
        clause('DASH') { |v| '-' }
        clause('DOT') { |v| '.' }
        clause('SLASH') { |v| '/' }
        clause('COLON') { |v| ':' }

        clause('IN') { |v| v }
        clause('AND') { |v| v }
        clause('OR') { |v| v }
        clause('NOT') { |v| v }
      end

      production(:in_list) do
        clause('value') { |v| InList.new([v]) }
        clause('.value SPACE? COMMA SPACE? .in_list') { |a, b| InList.new([a, *b.items]) }
      end

      finalize
    end
  end
end
