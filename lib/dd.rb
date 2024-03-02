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

if $0 == __FILE__
  all = DD::ObjectSet.from_dump
  ok = 0
  errors = 0
  all.each_monitor('query alert') do |mon|
    q = mon.query

    # p q
    # next

    # next unless q.include?('trace.serviceaccess.reconcile.apdex.by.service')
    # s = q.scan(/[{}]/).join
    # puts s

    q = q.gsub(/\n/, ' ')

    q = q.gsub(/(\w+:[A-Za-z0-9._-]+\{.*?\})/, 'AVG_NAME_FILTER')
    # puts q
    q = q.gsub(/\s+by\s+\{.*?\}/, ' BY')
    # puts q
    q = q.gsub(/AVG_NAME_FILTER(?: BY)?/, 'AMFB')
    # puts q
    q = q.gsub(/\b\d+\b/, 'NUM')
    # puts q

    q = q.gsub(/^(avg|sum|min|max)\(last_\d+\w\)/, 'AGGLAST')
    # puts q
    q = q.sub(/\s+[<>]=?\s+[+-]?(NUM|\.NUM|NUM\.NUM)$/, ' COMPNUM')
    # puts q

    begin
      q = DD::MetricAlertQuery.parse(mon.query)
      # p({ success: q })
      ok += 1
    rescue => e
      p({ query: mon.query, error: e.message[..100]+"..." })
      errors += 1
    end
  end

  puts "ok: #{ok}"
  puts "errors: #{errors}"
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
