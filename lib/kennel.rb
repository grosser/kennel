# frozen_string_literal: true
require "faraday"
require "json"
require "English"

require "kennel/utils"
require "kennel/progress"
require "kennel/syncer"
require "kennel/api"
require "kennel/github_reporter"
require "kennel/subclass_tracking"
require "kennel/file_cache"

require "kennel/models/base"
require "kennel/models/monitor"
require "kennel/models/dash"
require "kennel/models/project"
require "kennel/models/team"

module Kennel
  class << self
    def generate
      FileUtils.rm_rf("generated")
      generated.each do |part|
        path = "generated/#{part.tracking_id.sub(":", "/")}.json"
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(part.as_json) << "\n")
      end
    end

    def plan
      syncer.plan
    end

    def update
      syncer.plan
      syncer.update if syncer.confirm
    end

    def report_plan_to_github
      reporter = GithubReporter.new(ENV.fetch("GITHUB_TOKEN"))
      reporter.report { plan }
    end

    private

    def syncer
      @syncer ||= Syncer.new(api, generated)
    end

    def api
      @api ||= Api.new(ENV.fetch("DATADOG_APP_KEY"), ENV.fetch("DATADOG_API_KEY"))
    end

    def generated
      @generated ||= begin
        Progress.progress "Generating" do
          load_all
          Models::Project.recursive_subclasses.flat_map do |project_class|
            project_class.new.parts
          end
        end
      end
    end

    def load_all
      Dir["{parts,teams,projects}/**/*.rb"].each { |f| require "./#{f}" }
    end
  end
end
