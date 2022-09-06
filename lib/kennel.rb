# frozen_string_literal: true
require "faraday"
require "json"
require "zeitwerk"
require "English"

require "kennel/version"
require "kennel/compatibility"
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
require "kennel/parts_writer/generated_dir"

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

  include Kennel::Compatibility

  class Engine
    def initialize
      @out = $stdout
      @err = $stderr
      @strict_imports = true
    end

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
      Kennel::PartsWriter::GeneratedDir.new(
        project_filter: project_filter,
        tracking_id_filter: tracking_id_filter
      ).store(parts: parts)
    end

    def syncer
      @syncer ||= Syncer.new(api, generated, project_filter: project_filter, tracking_id_filter: tracking_id_filter)
    end

    def api
      @api ||= Api.new(ENV.fetch("DATADOG_APP_KEY"), ENV.fetch("DATADOG_API_KEY"))
    end

    def generated
      @generated ||= begin
        Progress.progress "Generating" do
          load_all

          projects = Models::Project.recursive_subclasses.map(&:new)
          filter_resources!(projects, :kennel_id, project_filter, "projects", "PROJECT")

          parts = Utils.parallel(projects, &:validated_parts).flatten(1)
          filter_resources!(parts, :tracking_id, tracking_id_filter, "resources", "TRACKING_ID")

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
      projects = ENV["PROJECT"]&.split(",")
      tracking_projects = tracking_id_filter&.map { |id| id.split(":", 2).first }
      if projects && tracking_projects && projects != tracking_projects
        raise "do not set PROJECT= when using TRACKING_ID="
      end
      projects || tracking_projects
    end

    def tracking_id_filter
      (tracking_id = ENV["TRACKING_ID"]) && tracking_id.split(",")
    end

    def filter_resources!(resources, by, against, name, env)
      return unless against

      before = resources.dup
      resources.select! { |p| against.include?(p.send(by)) }
      return if resources.size == against.size

      raise <<~MSG.rstrip
        #{env}=#{against.join(",")} matched #{resources.size} #{name}, try any of these:
        #{before.map(&by).sort.uniq.join("\n")}
      MSG
    end

    def load_all
      loader = Zeitwerk::Loader.new
      Dir.exist?("teams") && loader.push_dir("teams", namespace: Teams)
      Dir.exist?("parts") && loader.push_dir("parts")
      loader.setup
      loader.eager_load # TODO: this should not be needed but we see hanging CI processes when it's not added

      # TODO: also auto-load projects and update expected path too
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
