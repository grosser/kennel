if $0 == __FILE__
  $LOAD_PATH << File.dirname(__FILE__)
end

require_relative "dd/dump_object"
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
  puts "#{all.count} objects"
  puts "#{all.each_monitor.count} monitors"
  puts "#{all.each_monitor('metric alert').count} metric alert monitors"
  puts "#{all.each_dashboard_widget.count} widgets"
  puts "#{all.each_dashboard_widget('slo').count} SLO widgets"

  t = Hash.with_default_value { Hash.with_default_value { 0 } }
  all.each_monitor do |m|
    m.options.keys.each do |k|
      t[:all][k] += 1
      t[:all][:all] += 1
      t[m.type][k] += 1
      t[m.type][:all] += 1
    end
  end

  require 'byebug'
  byebug

  exit
end
