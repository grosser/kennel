# frozen_string_literal: true
require "faraday"
require "json"
require "zeitwerk"
require "English"

require "kennel/version"
require "kennel/compatibility"
require "kennel/utils"
require "kennel/progress"
require "kennel/filter"
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

  include Kennel::Compatibility

  UpdateResult = Struct.new(:plan, :update, keyword_init: true)

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
      the_plan = syncer.plan
      the_update = syncer.update if syncer.confirm
      UpdateResult.new(
        plan: the_plan,
        update: the_update
      )
    end

    private

    def store(parts)
      Progress.progress "Storing" do
        old = Dir[[
          "generated",
          if filter.project_filter || filter.tracking_id_filter
            [
              "{" + (filter.project_filter || ["*"]).join(",") + "}",
              "{" + (filter.tracking_id_filter || ["*"]).join(",") + "}.json"
            ]
          else
            "**"
          end
        ].join("/")]
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

    def filter
      @filter ||= Filter.new
    end

    def syncer
      @syncer ||= Syncer.new(api, generated, project_filter: filter.project_filter, tracking_id_filter: filter.tracking_id_filter)
    end

    def api
      @api ||= Api.new(ENV.fetch("DATADOG_APP_KEY"), ENV.fetch("DATADOG_API_KEY"))
    end

    def generated
      @generated ||= begin
        Progress.progress "Generating" do
          load_all

          projects = Models::Project.recursive_subclasses.map(&:new)
          Kennel::Filter.filter_resources!(projects, :kennel_id, filter.project_filter, "projects", "PROJECT")

          parts = Utils.parallel(projects, &:validated_parts).flatten(1)
          Kennel::Filter.filter_resources!(parts, :tracking_id, filter.tracking_id_filter, "resources", "TRACKING_ID")

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

    def load_all
      # load_all's purpose is to "require" all the .rb files under './projects',
      # also with reference to ./teams and ./parts. What happens if you call it
      # more than once?
      #
      # For a reason yet to be investigated, Zeitwerk rejects second and subsequent calls.
      # But even if we skip over the Zeitwerk part, the nature of 'require' is
      # somewhat one-way: we're not providing any mechanism to *un*load things.
      # As long as the contents of `./projects`, `./teams` and `./parts` doesn't
      # change between calls, then simply by no-op'ing subsequent calls to `load_all`
      # we can have `load_all` appear to be idempotent.
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
