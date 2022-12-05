# frozen_string_literal: true
require "faraday"
require "json"
require "zeitwerk"
require "English"

require "kennel/version"
require "kennel/utils"
require "kennel/progress"
require "kennel/filter"
require "kennel/parts_serializer"
require "kennel/projects_provider"
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
  UpdateResult = Struct.new(:plan, :update, keyword_init: true)

  class << self
    attr_accessor :out, :err
  end

  self.out = $stdout
  self.err = $stderr

  class Engine
    def initialize
      @strict_imports = true
    end

    attr_accessor :strict_imports

    def generate
      parts = generated
      parts_serializer.write(parts) if ENV["STORE"] != "false" # quicker when debugging
      parts
    end

    def plan
      syncer.plan
    end

    def update
      syncer.plan
      syncer.update if syncer.confirm
    end

    private

    def download_definitions(**kwargs)
      Progress.progress("Downloading definitions", **kwargs) do
        Utils.parallel(Models::Record.subclasses) do |klass|
          results = api.list(klass.api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
          results.each { |a| Utils.inline_resource_metadata(a, klass) }
        end.flatten(1)
      end
    end

    def filter
      @filter ||= Filter.new
    end

    def syncer
      @syncer ||= begin
        expected, actual = Utils.parallel([:generated, :download_definitions]) { |m| send m, plain: true }
        Syncer.new(api, expected, actual, kennel: self, project_filter: filter.project_filter, tracking_id_filter: filter.tracking_id_filter)
      end
    end

    def api
      @api ||= Api.new
    end

    def projects_provider
      @projects_provider ||= ProjectsProvider.new
    end

    def parts_serializer
      @parts_serializer ||= PartsSerializer.new(filter: filter)
    end

    def generated(**kwargs)
      @generated ||= begin
        parts = Progress.progress "Finding parts", **kwargs do
          projects = projects_provider.projects
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
  end
end
