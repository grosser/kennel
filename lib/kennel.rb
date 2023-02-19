# frozen_string_literal: true
require "faraday"
require "json"
require "zeitwerk"
require "English"

require "kennel/version"
require "kennel/console"
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
    def initialize(
      generate: true,
      show_plan: false,
      require_confirm: default_require_confirm?,
      update_datadog: false,
      strict_imports: true
    )
      @generate = generate
      @show_plan = show_plan
      @require_confirm = require_confirm
      @update_datadog = update_datadog
      @strict_imports = strict_imports
    end

    def run
      if !generate? && !show_plan? && !update_datadog?
        parts
        return
      end

      if show_plan? || update_datadog?
        # start generation and download in parallel to make planning faster
        Utils.parallel([:parts, :definitions]) { |m| send m, plain: true }
      end

      if generate?
        PartsSerializer.new(filter: filter).write(parts)
      end

      if show_plan? || update_datadog?
        syncer # Instantiating the syncer calculates the plan

        syncer.print_plan if show_plan?

        if update_datadog?
          syncer.update if !require_confirm? || syncer.confirm
        else
          syncer.plan # i.e. get & return the already-calculated plan
        end
      end
    end

    private

    attr_reader :strict_imports

    def default_require_confirm?
      $stdin.tty? && $stdout.tty?
    end

    def generate?
      @generate
    end

    def show_plan?
      @show_plan
    end

    def require_confirm?
      @require_confirm
    end

    def update_datadog?
      @update_datadog
    end

    def filter
      @filter ||= Filter.new
    end

    def syncer
      @syncer ||=
        Syncer.new(
          api, parts, definitions,
          filter: filter,
          strict_imports: strict_imports
        )
    end

    def api
      @api ||= Api.new
    end

    def parts(**kwargs)
      @parts ||= begin
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
          api.list(klass.api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
        end.flatten(1)
      end
    end
  end
end
