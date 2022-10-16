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
  class ValidationError < RuntimeError
    def initialize(part, tag, message)
      @part = part
      @tag = tag
      super(message)
    end

    attr_reader :part, :tag
  end

  UnresolvableIdError = Class.new(RuntimeError)
  DisallowedUpdateError = Class.new(RuntimeError)

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
      parts = generated
      parts_serializer.write(parts) if ENV["STORE"] != "false" # quicker when debugging
      parts
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

    def filter
      @filter ||= Filter.new
    end

    def syncer
      @syncer ||= Syncer.new(api, generated, project_filter: filter.project_filter, tracking_id_filter: filter.tracking_id_filter)
    end

    def api
      @api ||= Api.new(ENV.fetch("DATADOG_APP_KEY"), ENV.fetch("DATADOG_API_KEY"))
    end

    def projects_provider
      @projects_provider ||= ProjectsProvider.new
    end

    def parts_serializer
      @parts_serializer ||= PartsSerializer.new(filter: filter)
    end

    def generated
      @generated ||= begin
        Progress.progress "Generating" do
          projects = projects_provider.projects
          projects = filter.filter_projects projects

          parts = Utils.parallel(projects, &:validated_parts).flatten(1)
          parts = filter.filter_parts parts

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
  end
end
