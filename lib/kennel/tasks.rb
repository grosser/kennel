# frozen_string_literal: true
require "English"
require "kennel"
require "kennel/unmuted_alerts"
require "kennel/importer"
require "json"

module Kennel
  module Tasks
    class << self
      def abort(message = nil)
        Kennel.err.puts message if message
        raise SystemExit.new(1), message
      end
    end
  end
end

namespace :kennel do
  desc "Ensure there are no uncommited changes that would be hidden from PR reviewers"
  task no_diff: :generate do
    result = `git status --porcelain generated/`.strip
    Kennel::Tasks.abort "Diff found:\n#{result}\nrun `rake generate` and commit the diff to fix" unless result == ""
    Kennel::Tasks.abort "Error during diffing" unless $CHILD_STATUS.success?
  end

  # ideally do this on every run, but it's slow (~1.5s) and brittle (might not find all + might find false-positives)
  # https://help.datadoghq.com/hc/en-us/requests/254114 for automatic validation
  desc "Verify that all used monitor  mentions are valid"
  task validate_mentions: :environment do
    known = Kennel.send(:api)
      .send(:request, :get, "/monitor/notifications")
      .fetch(:handles)
      .values
      .flatten(1)
      .map { |v| v.fetch(:value) }

    known += ENV["KNOWN"].to_s.split(",")

    bad = []
    Dir["generated/**/*.json"].each do |f|
      next unless message = JSON.parse(File.read(f))["message"]
      used = message.scan(/\s(@[^\s{,'"]+)/).flatten(1)
        .grep(/^@.*@|^@.*-/) # ignore @here etc handles ... datadog uses @foo@bar.com for emails and @foo-bar for integrations
      (used - known).each { |v| bad << [f, v] }
    end

    if bad.any?
      url = Kennel::Utils.path_to_url "/account/settings"
      puts "Invalid mentions found, either ignore them by adding to `KNOWN` env var or add them via #{url}"
      bad.each { |f, v| puts "Invalid mention #{v} in monitor message of #{f}" }
      Kennel::Tasks.abort ENV["KNOWN_WARNING"]
    end
  end

  desc "generate local definitions"
  task generate: :environment do
    Kennel.generate
  end

  desc "run the 'fragile' report"
  task report_fragile: :environment do
    require 'kennel/dependency_checker'
    require 'kennel/resources'

    everything = Kennel::Resources.cached_each(
      filename: "tmp/cache/report_fragile.json",
      max_age: 3600
    ).to_a

    dependencies = Kennel::DependencyChecker::Collector.new(everything)
      .collect

    report = Kennel::DependencyChecker::Reporter.new(base_url: ENV['BASE_URL'])
      .report(dependencies)

    out = "tmp/fragile.json"
    Tempfile.open(out, File.dirname(out)) do |f|
      f.puts JSON.generate(dependencies: report)
      f.flush
      f.chmod 0o644
      File.rename f.path, out
    end
    puts "Wrote to #{out}"
  end

  desc "show resources to standard output (like 'dump')"
  task dump_resources: :environment do
    require 'json'
    require 'kennel/resources'

    resources = if ENV.key?('TYPE')
                  ENV['TYPE'].split(',')
                end

    Kennel::Resources.each(resources: resources) do |resource|
      puts JSON.generate(resource)
    end
  end

  task dump_resources_cached: :environment do
    all_tags = Set.new
    require 'kennel/resources'

    Kennel::Resources.cached_each(filename: "tmp/cache/dump_resources_cached.json", max_age: 3600) do |r|
      txt = "#{r[:message]} #{r[:description]}"
      next unless txt.include?("Managed by kennel")

      next unless txt.include?("enigma")

      tags = r.fetch(:tags, []) + r.fetch(:monitor_tags, [])
      all_tags += tags
      # puts "#{r.fetch(:api_resource)} #{r.fetch(:id)} #{tags.inspect}"
    end

    unspaced = Set.new
    spaced = Hash.new { |h, k| h[k] = Set.new }

    all_tags.each do |tag|
      pre, post = tag.split(":", 2)
      if post.nil?
        unspaced << pre
      else
        spaced[pre] << post
      end
    end

    puts "COUNT UNSPACED #{unspaced.count}"
    unspaced.sort.each do |k|
      puts "UNSPACED\t#{k}"
    end

    puts "COUNT SPACED #{spaced.count}"
    spaced.keys.sort.each do |k|
      puts "SPACED\t#{k}\tCOUNT #{spaced[k].count}"
      spaced[k].sort.each do |v|
        puts "PAIR\t#{k}\t#{v}"
      end
    end
  end

  # also generate parts so users see and commit updated generated automatically
  desc "show planned datadog changes (scope with PROJECT=name)"
  task plan: :generate do
    Kennel.plan
  end

  desc "update datadog (scope with PROJECT=name)"
  task update_datadog: :environment do
    Kennel.update
  end

  desc "update on push to the default branch, otherwise show plan"
  task :ci do
    branch = (ENV["TRAVIS_BRANCH"] || ENV["GITHUB_REF"]).to_s.sub(/^refs\/heads\//, "")
    on_default_branch = (branch == (ENV["DEFAULT_BRANCH"] || "master"))
    is_push = (ENV["TRAVIS_PULL_REQUEST"] == "false" || ENV["GITHUB_EVENT_NAME"] == "push")
    task_name =
      if on_default_branch && is_push
        Kennel.strict_imports = false
        "kennel:update_datadog"
      else
        "kennel:plan" # show plan in CI logs
      end

    Rake::Task[task_name].invoke
  end

  desc "show unmuted alerts filtered by TAG, for example TAG=team:foo"
  task alerts: :environment do
    tag = ENV["TAG"] || Kennel::Tasks.abort("Call with TAG=foo:bar")
    Kennel::UnmutedAlerts.print(Kennel.send(:api), tag)
  end

  desc "show monitors with no data by TAG, for example TAG=team:foo [THRESHOLD_DAYS=7] [FORMAT=json]"
  task nodata: :environment do
    tag = ENV["TAG"] || Kennel::Tasks.abort("Call with TAG=foo:bar")
    monitors = Kennel.send(:api).list("monitor", monitor_tags: tag, group_states: "no data")
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

    if threshold = ENV["THRESHOLD_DAYS"]
      monitors.select! { |m| m[:days_in_no_data] > Integer(threshold) }
    end

    monitors.each { |m| m[:url] = Kennel::Utils.path_to_url("/monitors/#{m[:id]}") }

    if ENV["FORMAT"] == "json"
      report = monitors.map do |m|
        match = m[:message].to_s.match(/-- Managed by kennel (\S+:\S+) in (\S+), /) || []
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

  desc "Convert existing resources to copy-pasteable definitions to import existing resources (call with URL= or call with RESOURCE= and ID=)"
  task import: :environment do
    if (id = ENV["ID"]) && (resource = ENV["RESOURCE"])
      id = Integer(id) if id =~ /^\d+$/ # dashboards can have alphanumeric ids
    elsif (url = ENV["URL"])
      resource, id = Kennel::Models::Record.parse_any_url(url) || Kennel::Tasks.abort("Unable to parse url")
    else
      possible_resources = Kennel::Models::Record.subclasses.map(&:api_resource)
      Kennel::Tasks.abort("Call with URL= or call with RESOURCE=#{possible_resources.join(" or ")} and ID=")
    end

    Kennel.out.puts Kennel::Importer.new(Kennel.send(:api)).import(resource, id)
  end

  desc "Dump ALL of datadog config as raw json ... useful for grep/search [TYPE=slo|monitor|dashboard]"
  task dump: :environment do
    resources =
      if type = ENV["TYPE"]
        [type]
      else
        Kennel::Models::Record.api_resource_map.keys
      end
    api = Kennel.send(:api)
    list = nil

    resources.each do |resource|
      Kennel::Progress.progress("Downloading #{resource}") do
        list = api.list(resource)
        api.fill_details!(resource, list) if resource == "dashboard"
      end
      list.each do |r|
        r[:api_resource] = resource
        Kennel.out.puts JSON.pretty_generate(r)
      end
    end
  end

  desc "Find items from dump by pattern DUMP= PATTERN= [URLS=true]"
  task dump_grep: :environment do
    file = ENV.fetch("DUMP")
    pattern = Regexp.new ENV.fetch("PATTERN")
    items = File.read(file).gsub("}\n{", "}--SPLIT--{").split("--SPLIT--")
    models = Kennel::Models::Record.api_resource_map
    found = items.grep(pattern)
    exit 1 if found.empty?
    found.each do |resource|
      if ENV["URLS"]
        parsed = JSON.parse(resource)
        url = models[parsed.fetch("api_resource")].url(parsed.fetch("id"))
        title = parsed["title"] || parsed["name"]
        Kennel.out.puts "#{url} # #{title}"
      else
        Kennel.out.puts resource
      end
    end
  end

  task :environment do
    require "kennel"
    gem "dotenv"
    require "dotenv"
    source = ".env"

    # warn when users have things like DATADOG_TOKEN already set and it will not be loaded from .env
    unless ENV["KENNEL_SILENCE_UPDATED_ENV"]
      updated = Dotenv.parse(source).select { |k, v| ENV[k] && ENV[k] != v }
      warn "Environment variables #{updated.keys.join(", ")} need to be unset to be sourced from #{source}" if updated.any?
    end

    Dotenv.load(source)
  end
end
