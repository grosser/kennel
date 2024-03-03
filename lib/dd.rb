if $0 == __FILE__
  $LOAD_PATH << File.dirname(__FILE__)
end

JData = Data

require_relative "dd/dump_object"
require_relative "dd/metric_alert_query"
require_relative "dd/metric_analysis"
require_relative "dd/metric_filter"
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
      DD::MetricFilter.parse(f)
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
