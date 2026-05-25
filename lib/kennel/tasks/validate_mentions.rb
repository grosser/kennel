# frozen_string_literal: true

namespace :kennel do
  desc "Verify that all used monitor  mentions are valid"
  task validate_mentions: :environment do
    known = []

    # @slack- @team- @webhook- @sns- user-emails
    known += Kennel::Api.new.send(:request, :get, "/api/v2/notifications/handles?group_limit=99999")
      .fetch(:data)
      .flat_map { |d| d.dig(:attributes, :handles) }
      .map { |v| v.fetch(:value) }

    # group emails or other 1-off things we know are valid
    manual = ENV["KNOWN"].to_s.split(",")
    dupes = (manual & known)
    Kennel::Tasks.abort "KNOWN=#{dupes.join(",")} values are already known and should be removed" if dupes.any?
    known += manual

    # @sns- handles are randomly invalid so we need to ignore them without checking if the ignore is needed
    # https://help.datadoghq.com/hc/en-us/requests/2310423
    known += ENV["KNOWN_RANDOM"].to_s.split(",")

    bad = []
    Dir["generated/**/*.json"].each do |f|
      next unless (message = JSON.parse(File.read(f))["message"])
      used = message
        .scan(/(?:^|\s)(@[^\s{,'"]+)/)
        .flatten(1)
        .grep(/^@.*@|^@.*-/) # ignore @here etc handles ... datadog uses @foo@bar.com for emails and @foo-bar for integrations
      (used - known).each { |v| bad << [f, v] }
    end

    if bad.any?
      url = Kennel::Utils.path_to_url "/account/settings"
      Kennel.err.puts "Invalid mentions found, either ignore them by adding to `KNOWN` env var or add them via #{url}"
      bad.each { |f, v| Kennel.err.puts "Invalid mention #{v} in monitor message of #{f}" }
      Kennel::Tasks.abort ENV["KNOWN_WARNING"]
    end
  end
end
