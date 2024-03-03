if $0 == __FILE__
  $LOAD_PATH << File.dirname(__FILE__)
end

require_relative "dd/dump_object"
require_relative "dd/metric_alert_query"
require_relative "dd/metric_analysis"
require_relative "dd/object_set"

class Hash
  def self.with_default_value(v = :nothing, &block)
    if v != :nothing && block.nil?
      Hash.new { |h, k| h[k] = v }
    elsif v == :nothing && block
      Hash.new { |h, k| h[k] = block.call }
    else
      raise "Expected either a value or a block"
    end
  end

  def puts_distribution
    max = values.max

    transform_keys(&:inspect).entries.sort_by(&:first)..each do |k, n|
      pct = 100.0 * n / max
      puts("  %6d  %3d%%  %s" % [n, pct, k])
    end

    nil
  end
end

JData = Data

module MetricFilterParser
  class BooleanLexer < RLTK::Lexer
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
    # r(/([\w\*.\/:-]+)/) { |v| [:COMPLEX_WORD, v] }
  end

  SimpleValue = JData.define(:value)
  TemplateValue = JData.define(:name)
  TemplateVariable = JData.define(:name)
  CommaList = JData.define(:items)
  OrList = JData.define(:items)
  AndList = JData.define(:items)
  Bang = JData.define(:item)
  Not = JData.define(:item)
  KeyValuePair = JData.define(:key, :value)
  KeyOnly = JData.define(:key)
  InClause = Data.define(:needle, :haystack)
  InList = Data.define(:items)
  Star = Data.define()

  class BooleanParser < RLTK::Parser
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

      # clause('BANG .expression') { |e|  }
      # clause('.expression SPACE AND SPACE .expression') { |x, y| [:AND, x, y] }
      # clause('.expression SPACE OR SPACE .expression') { |x, y| [:OR, x, y] }
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

    finalize(debug: $stdout)
  end

  def self.parse(f)
    tokens = BooleanLexer.lex(f)
    BooleanParser.parse(tokens)
  rescue => e
    { filter_parse_error: e, input: f }
  end
end

require 'set'
def expand(v, seen: Set.new)
  case v
  when JData
    raise "Seen #{v.__id__} #{v}" unless seen.add?(v.__id__)
    v.to_h.transform_values { |vv| expand(vv, seen:) }
  when Hash
    raise "Seen #{v.__id__} #{v}" unless seen.add?(v.__id__)
    v.transform_values { |vv| expand(vv, seen:) }
  when Array
    raise "Seen #{v.__id__} #{v}" unless seen.add?(v.__id__)
    v.map { |vv| expand(vv, seen:) }
  when String, Float, Integer, true, false, nil
    v
  # when Symbol
  #   "symbol-#{v}"
  when Exception
    { exception: { s: v.to_s, message: v.message, backtrace: v.backtrace } }
  else
    raise [:else, v].inspect
  end
end

if $0 == __FILE__
  all = DD::ObjectSet.from_dump
  ok = 0
  errors = 0
  all.each_monitor('query alert') do |mon|
    q = mon.query
    # puts q

    match = q.match(/^(?<aggregate>.*?):(?<expression>.*)(?<comparator>[<>]=?|==)\s*(?<threshold>[+-]?[0-9\.]+)\s*$/sm)

    if match.nil?
      puts JSON.generate({ error: "Fails basic structure", id: mon.id, query: q })
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
      MetricFilterParser.parse(f)
    end

    out = {
      input: { id: mon.id, query: q },
      output: {
        aggregate:,
        expression:,
        comparator:,
        threshold:,
        by_pod_fragments:,
        filter_fragments:
      }
    }
    puts JSON.generate(expand(out))
  end

  # puts "ok: #{ok}"
  # puts "errors: #{errors}"
  exit

  # simple = 'avg(last_30m):sum:kafka.consumer.lag{accurate:true,consumer:mau.free-text-prediction-events-consumer,env:production} by {pod} > 1000'
  # q = DD::MetricAlertQuery.parse(simple)
  # p q

  # all = DD::ObjectSet.from_dump
  # puts "#{all.count} objects"
  # puts "#{all.each_monitor.count} monitors"
  # puts "#{all.each_monitor('metric alert').count} metric alert monitors"
  # puts "#{all.each_dashboard_widget.count} widgets"
  # puts "#{all.each_dashboard_widget('slo').count} SLO widgets"
  #
  # t = Hash.with_default_value { Hash.with_default_value { 0 } }
  # all.each_monitor do |m|
  #   m.options.keys.each do |k|
  #     t[:all][k] += 1
  #     t[:all][:all] += 1
  #     t[m.type][k] += 1
  #     t[m.type][:all] += 1
  #   end
  # end

  require 'byebug'
  byebug

  exit
end
