# frozen_string_literal: true
require "kennel"

# Show Alerts that are not muted and their alerting scopes
module Kennel
  class UnmutedAlerts
    COLORS = {
      "Alert" => :red,
      "Warn" => :yellow,
      "No Data" => :cyan
    }.freeze

    class << self
      def print(api, tag)
        monitors = filtered_monitors(api, tag)
        if monitors.empty?
          puts "No unmuted alerts found"
        else
          monitors.each do |m|
            puts m[:name]
            puts Utils.path_to_url("/monitors/#{m[:id]}")
            m[:state][:groups].each do |g|
              color = COLORS[g[:status]] || :default
              since = "\t#{time_since(g[:last_triggered_ts])}"
              puts "#{Kennel::Utils.color(color, g[:status])}\t#{g[:name]}#{since}"
            end
            puts
          end
        end
      end

      private

      # sort pod3 before pod11
      def sort_groups!(monitor)
        groups = monitor[:state][:groups].values
        groups.sort_by! { |g| g[:name].to_s.split(",").map { |w| Utils.natural_order(w) } }
        monitor[:state][:groups] = groups
      end

      def time_since(t)
        diff = Time.now.to_i - Integer(t)
        "%02d:%02d:%02d" % [diff / 3600, diff / 60 % 60, diff % 60]
      end

      def filtered_monitors(api, tag)
        # Download all monitors with given tag
        monitors = Progress.progress("Downloading") do
          api.list("monitor", monitor_tags: tag, group_states: "all")
        end

        raise "No monitors for #{tag} found, check your spelling" if monitors.empty?

        # only keep monitors that are not completely silenced
        monitors.reject! { |m| m[:options][:silenced].key?(:*) }

        # only keep groups that are alerting
        monitors.each { |m| m[:state][:groups].reject! { |_, g| g[:status] == "OK" } }

        # only keep alerting groups that are not silenced
        monitors.each do |m|
          silenced = m[:options][:silenced].keys.map { |k| k.to_s.split(",") }
          m[:state][:groups].select! do |k, _|
            scope = k.to_s.split(",")
            silenced.none? { |s| (s - scope).empty? }
          end
        end

        # only keep monitors with alerting groups
        monitors.select! { |m| m[:state][:groups].any? }

        # sort group alerts
        monitors.each { |m| sort_groups!(m) }
      end
    end
  end
end
