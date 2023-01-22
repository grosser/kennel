# frozen_string_literal: true

module Kennel
  class Filter
    attr_reader :project_filter, :tracking_id_filter

    def initialize
      # build early so we fail fast on invalid user input
      @tracking_id_filter = build_tracking_id_filter
      @project_filter = build_project_filter
    end

    def filter_projects(projects)
      filter_resources(projects, :kennel_id, project_filter, "projects", "PROJECT")
    end

    def filter_parts(parts)
      filter_resources(parts, :tracking_id, tracking_id_filter, "resources", "TRACKING_ID")
    end

    private

    def build_project_filter
      project_names = ENV["PROJECT"]&.split(",")&.sort&.uniq
      tracking_project_names = tracking_id_filter&.map { |id| id.split(":", 2).first }&.sort&.uniq
      if project_names && tracking_project_names && project_names != tracking_project_names
        raise "do not set PROJECT= when using TRACKING_ID="
      end
      (project_names || tracking_project_names)
    end

    def build_tracking_id_filter
      (tracking_id = ENV["TRACKING_ID"]) && tracking_id.split(",").sort.uniq
    end

    def filter_resources(resources, by, expected, _name, _env)
      return resources unless expected

      resources.select { |p| expected.uniq.include?(p.send(by)) }
    end
  end
end
