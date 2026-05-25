# frozen_string_literal: true

namespace :kennel do
  desc "show monitors with no data by TAG, for example TAG=team:foo [THRESHOLD_DAYS=7] [FORMAT=json]"
  task nodata: :environment do
    tag = ENV["TAG"] || Kennel::Tasks.abort("Call with TAG=foo:bar")
    monitors = Kennel::Api.new.list("monitor", monitor_tags: tag, group_states: "no data")
    monitors.select! { |m| m[:overall_state] == "No Data" }
    monitors.reject! { |m| m[:tags].include? "nodata:ignore" }
    if monitors.any?
      Kennel.err.puts <<~TEXT
        To ignore monitors with expected nodata, tag it with "nodata:ignore"

      TEXT
    end

    now = Time.now
    monitors.each do |m|
      m[:days_in_no_data] =
        if m[:overall_state_modified]
          since = Date.parse(m[:overall_state_modified]).to_time
          ((now - since) / (24 * 60 * 60)).to_i
        else
          999
        end
    end

    if (threshold = ENV["THRESHOLD_DAYS"])
      monitors.select! { |m| m[:days_in_no_data] > Integer(threshold) }
    end

    monitors.each { |m| m[:url] = Kennel::Utils.path_to_url("/monitors/#{m[:id]}") }

    if ENV["FORMAT"] == "json"
      report = monitors.map do |m|
        match = m[:message].to_s.match(/-- #{Regexp.escape(Kennel::Models::Record::MARKER_TEXT)} (\S+:\S+) in (\S+), /) || []
        m.slice(:url, :name, :tags, :days_in_no_data).merge(
          kennel_tracking_id: match[1],
          kennel_source: match[2]
        )
      end

      Kennel.out.puts JSON.pretty_generate(report)
    else
      monitors.each do |m|
        Kennel.out.puts m[:name]
        Kennel.out.puts Kennel::Utils.path_to_url("/monitors/#{m[:id]}")
        Kennel.out.puts "No data since #{m[:days_in_no_data]}d"
        Kennel.out.puts
      end
    end
  end
end
