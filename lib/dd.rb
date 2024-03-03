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
    {
      class: v.class.to_s,
      data: v.to_h.transform_values { |vv| expand(vv, seen:) }
    }
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

  all.each_monitor('query alert') do |mon|
    q = mon.query

    out = {
      input: { id: mon.id, query: q },
      output: DD::MetricAlertQuery.lazy_parse(q),
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
