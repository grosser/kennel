# frozen_string_literal: true
require "faraday"
require "json"
require "zeitwerk"
require "English"

require "kennel/version"
require "kennel/console_utils"
require "kennel/string_utils"
require "kennel/utils"
require "kennel/progress"
require "kennel/filter"
require "kennel/parts_serializer"
require "kennel/projects_provider"
require "kennel/attribute_differ"
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
  UnresolvableIdError = Class.new(StandardError)
  DisallowedUpdateError = Class.new(StandardError)
  GenerationAbortedError = Class.new(StandardError)

  class << self
    attr_accessor :out, :err
  end

  self.out = $stdout
  self.err = $stderr

  class Engine
    attr_accessor :strict_imports

    def initialize
      @strict_imports = true
    end

    # start generation and download in parallel to make planning faster
    def preload
      Utils.parallel([:generated, :definitions]) { |m| send m, plain: true }
    end

    def generate
      parts = generated
      PartsSerializer.new(filter: filter).write(parts) if ENV["STORE"] != "false" # quicker when debugging
      parts
    end

    def plan
      syncer.print_plan
      syncer.plan
    end

    def update
      syncer.print_plan
      syncer.update if syncer.confirm
    end

    private

    def filter
      @filter ||= Filter.new
    end

    def syncer
      @syncer ||= begin
        preload
        Syncer.new(
          api, generated, definitions,
          strict_imports: strict_imports,
          project_filter: filter.project_filter,
          tracking_id_filter: filter.tracking_id_filter
        )
      end
    end

    def api
      @api ||= Api.new
    end

    def generated(**kwargs)
      @generated ||= begin
        parts = Progress.progress "Finding parts", **kwargs do
          projects = ProjectsProvider.new.projects
          projects = filter.filter_projects projects

          parts = Utils.parallel(projects, &:validated_parts).flatten(1)
          filter.filter_parts parts
        end

        parts.group_by(&:tracking_id).each do |tracking_id, same|
          next if same.size == 1
          raise <<~ERROR
            #{tracking_id} is defined #{same.size} times
            use a different `kennel_id` when defining multiple projects/monitors/dashboards to avoid this conflict
          ERROR
        end

        Progress.progress "Building json" do
          # trigger json caching here so it counts into generating
          Utils.parallel(parts, &:build)
        end

        OptionalValidations.valid?(parts) or raise GenerationAbortedError

        parts
      end
    end

    def definitions(**kwargs)
      @definitions ||= Progress.progress("Downloading definitions", **kwargs) do
        Utils.parallel(Models::Record.subclasses) do |klass|
          results = api.list(klass.api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
          results.each { |a| Utils.inline_resource_metadata(a, klass) }
        end.flatten(1)
      end
    end
  end
end
