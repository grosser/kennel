# frozen_string_literal: true
require "faraday"
require "json"
require "zeitwerk"
require "English"

require "kennel/version"
require "kennel/utils"
require "kennel/progress"
require "kennel/syncer"
require "kennel/id_map"
require "kennel/api"
require "kennel/github_reporter"
require "kennel/subclass_tracking"
require "kennel/settings_as_methods"
require "kennel/file_cache"
require "kennel/template_variables"
require "kennel/optional_validations"
require "kennel/unmuted_alerts"

require "kennel/models/base"
require "kennel/models/record"

# records
require "kennel/models/dashboard"
require "kennel/models/monitor"
require "kennel/models/slo"
require "kennel/models/synthetic_test"

# settings
require "kennel/models/project"
require "kennel/models/team"

# need to define early since we autoload the teams/ folder into it
module Teams
end

module Kennel
  class ValidationError < RuntimeError
  end

  @out = $stdout
  @err = $stderr
  @strict_imports = true

  class << self
    attr_accessor :out, :err, :strict_imports

    def generate
      out = generated
      store out if ENV["STORE"] != "false" # quicker when debugging
      out
    end

    def plan
      syncer.plan
    end

    def update
      syncer.plan
      syncer.update if syncer.confirm
    end

    private

    def store(parts)
      Progress.progress "Storing" do
        old = Dir["generated/{#{(project_filter || ["**"]).join(",")}}/*"]
        used = []

        Utils.parallel(parts, max: 2) do |part|
          path = "generated/#{part.tracking_id.tr("/", ":").sub(":", "/")}.json"
          used.concat [File.dirname(path), path] # only 1 level of sub folders, so this is safe
          payload = part.as_json.merge(api_resource: part.class.api_resource)
          write_file_if_necessary(path, JSON.pretty_generate(payload) << "\n")
        end

        # deleting all is slow, so only delete the extras
        (old - used).each { |p| FileUtils.rm_rf(p) }
      end
    end

    def write_file_if_necessary(path, content)
      # 99% case
      begin
        return if File.read(path) == content
      rescue Errno::ENOENT
        FileUtils.mkdir_p(File.dirname(path))
      end

      # slow 1% case
      File.write(path, content)
    end

    def syncer
      @syncer ||= Syncer.new(api, generated, project_filter: project_filter)
    end

    def api
      @api ||= Api.new(ENV.fetch("DATADOG_APP_KEY"), ENV.fetch("DATADOG_API_KEY"))
    end

    def generated
      @generated ||= begin
        Progress.progress "Generating" do
          load_all
          known = []
          filter = project_filter

          parts = Utils.parallel(Models::Project.recursive_subclasses) do |project_class|
            project = project_class.new
            kennel_id = project.kennel_id
            if filter
              known << kennel_id
              next [] unless filter.include?(kennel_id)
            end
            project.validated_parts
          end.flatten(1)

          if filter && parts.empty?
            raise "#{filter.join(", ")} does not match any projects, try any of these:\n#{known.uniq.sort.join("\n")}"
          end

          parts.group_by(&:tracking_id).each do |tracking_id, same|
            next if same.size == 1
            raise <<~ERROR
              #{tracking_id} is defined #{same.size} times
              use a different `kennel_id` when defining multiple projects/monitors/dashboards to avoid this conflict
            ERROR
          end

          # trigger json caching here so it counts into generating
          Utils.parallel(parts, &:as_json)

          parts
        end
      end
    end

    def project_filter
      ENV["PROJECT"]&.split(",")
    end

    def load_all
      loader = Zeitwerk::Loader.new
      Dir.exist?("teams") && loader.push_dir("teams", namespace: Teams)
      Dir.exist?("parts") && loader.push_dir("parts")
      loader.setup

      # TODO: also do projects and update expected path too
      ["projects"].each do |folder|
        Dir["#{folder}/**/*.rb"].sort.each { |f| require "./#{f}" }
      end
    rescue NameError => e
      message = e.message
      raise unless klass = message[/uninitialized constant (.*)/, 1]

      # inverse of zeitwerk lib/zeitwerk/inflector.rb
      path = klass.gsub("::", "/").gsub(/([a-z])([A-Z])/, "\\1_\\2").downcase + ".rb"
      expected_path = (path.start_with?("teams/") ? path : "parts/#{path}")

      # TODO: prefer to raise a new exception with the old backtrace attacked
      e.define_singleton_method(:message) do
        "\n" + <<~MSG.gsub(/^/, "  ")
          #{message}
          Unable to load #{klass} from #{expected_path}
          - Option 1: rename the constant or the file it lives in, to make them match
          - Option 2: Use `require` or `require_relative` to load the constant
        MSG
      end

      raise
    end
  end
end
