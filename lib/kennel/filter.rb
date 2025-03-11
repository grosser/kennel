# frozen_string_literal: true

module Kennel
  class Filter
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

    def filtering?
      !project_filter.nil?
    end

    def matches_project_id?(project_id)
      !filtering? || project_filter.include?(project_id)
    end

    def matches_tracking_id?(tracking_id)
      return true unless filtering?
      return tracking_id_filter.include?(tracking_id) if tracking_id_filter

      project_filter.include?(tracking_id.split(":").first)
    end

    private

    attr_reader :project_filter, :tracking_id_filter

    def build_project_filter
      project_names = ENV["PROJECT"]
      project_names = project_names.split(",").sort.uniq if project_names
      tracking_project_names = tracking_id_filter&.map { |id| id.split(":", 2).first }&.sort&.uniq
      if project_names && tracking_project_names && project_names != tracking_project_names
        raise "do not set PROJECT= when using TRACKING_ID="
      end
      project_names || tracking_project_names
    end

    def build_tracking_id_filter
      (tracking_id = ENV["TRACKING_ID"]) && tracking_id.split(",").map { |id| tracking_id_path_conversion(id) }.sort.uniq
    end

    # allow users to paste the generated path of an objects to update it without manually converting
    def tracking_id_path_conversion(tracking_id)
      return tracking_id unless tracking_id.end_with?(".json")
      tracking_id.sub("generated/", "").sub(".json", "").sub("/", ":")
    end

    def filter_resources(resources, by, expected, name, env)
      return resources unless expected

      expected = expected.uniq
      before = resources.dup
      resources = resources.select { |p| expected.include?(p.send(by)) }
      keeping = resources.uniq(&by).size
      return resources if keeping == expected.size

      raise <<~MSG.rstrip
        #{env}=#{expected.join(",")} matched #{keeping} #{name}, try any of these:
        #{before.map(&by).sort.uniq.join("\n")}
      MSG
    end
  end
end
