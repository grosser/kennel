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
require "kennel/template_variables"
require "kennel/optional_validations"

require "kennel/models/base"

# parts
require "kennel/models/monitor"
require "kennel/models/dash"
require "kennel/models/screen"

# settings
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

    private

    def syncer
      @syncer ||= Syncer.new(api, generated, project: ENV["PROJECT"])
    end

    def api
      @api ||= Api.new(ENV.fetch("DATADOG_APP_KEY"), ENV.fetch("DATADOG_API_KEY"))
    end

    def generated
      @generated ||= begin
        Progress.progress "Generating" do
          load_all
          parts = Models::Project.recursive_subclasses.flat_map do |project_class|
            project_class.new.parts
          end
          parts.map(&:tracking_id).group_by { |id| id }.select do |id, same|
            raise "#{id} is defined #{same.size} times" if same.size != 1
          end
          parts
        end
      end
    end

    def load_all
      ["teams", "parts", "projects"].each do |folder|
        Dir["#{folder}/**/*.rb"].sort.each { |f| require "./#{f}" }
      end
    end
  end
end
