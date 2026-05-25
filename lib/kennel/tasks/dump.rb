# frozen_string_literal: true

namespace :kennel do
  desc "Dump ALL of datadog config as raw json ... useful for grep/search [TYPE=slo|monitor|dashboard]"
  task dump: :environment do
    resources =
      if (type = ENV["TYPE"])
        [type]
      else
        Kennel::Models::Record.api_resource_map.keys
      end
    api = Kennel::Api.new
    list = nil
    first = true

    Kennel.out.puts "["
    resources.each do |resource|
      Kennel::Progress.progress("Downloading #{resource}") do
        list = api.list(resource)
        api.fill_details!(resource, list) if resource == "dashboard"
      end
      list.each do |r|
        r[:api_resource] = resource
        if first
          first = false
        else
          Kennel.out.puts ","
        end
        Kennel.out.print JSON.pretty_generate(r)
      end
    end
    Kennel.out.puts "\n]"
  end

  desc "Find items from dump by pattern DUMP= PATTERN= [URLS=true]"
  task dump_grep: :environment do
    file = ENV.fetch("DUMP")
    pattern = Regexp.new ENV.fetch("PATTERN")
    items = File.read(file)[2..-2].gsub("},\n{", "}--SPLIT--{").split("--SPLIT--")
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
end
