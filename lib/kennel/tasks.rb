# frozen_string_literal: true
require "English"
require "kennel"
require "kennel/unmuted_alerts"
require "kennel/importer"

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
      Kennel::Tasks.abort
    end
  end

  desc "generate local definitions"
  task generate: :environment do
    Kennel.generate
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

  desc "show monitors with no data by TAG, for example TAG=team:foo"
  task nodata: :environment do
    tag = ENV["TAG"] || Kennel::Tasks.abort("Call with TAG=foo:bar")
    monitors = Kennel.send(:api).list("monitor", monitor_tags: tag, group_states: "no data")
    monitors.select! { |m| m[:overall_state] == "No Data" }
    monitors.reject! { |m| m[:tags].include? "nodata:ignore" }
    if monitors.any?
      Kennel.err.puts <<~TEXT
        This is a useful task to find monitors that have mis-spelled metrics or never received data at any time.
        To ignore monitors with nodata, tag the monitor with "nodata:ignore"

      TEXT
    end

    monitors.each do |m|
      Kennel.out.puts m[:name]
      Kennel.out.puts Kennel::Utils.path_to_url("/monitors/#{m[:id]}")
      Kennel.out.puts
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
        api.fill_details!(resource, list)
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
