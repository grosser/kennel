# frozen_string_literal: true

module Kennel
  class Filter
    attr_reader :project_filter

    def initialize
      # read early so we fail fast on invalid user input
      @tracking_id_filter = read_tracking_id_filter_from_env
      @project_filter = read_project_filter_from_env
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

      project_id = tracking_id.split(":").first
      project_filter.include?(project_id)
    end

    def tracking_id_for_path(tracking_id)
      return tracking_id unless tracking_id.end_with?(".json")
      tracking_id.sub("generated/", "").sub(".json", "").sub("/", ":")
    end

    private

    attr_reader :tracking_id_filter

    # needs to be called after read_tracking_id_filter_from_env
    def read_project_filter_from_env
      project_names = ENV["PROJECT"]&.split(",")&.sort&.uniq
      tracking_project_names = tracking_id_filter&.map { |id| id.split(":", 2).first }&.sort&.uniq
      if project_names && tracking_project_names && project_names != tracking_project_names
        # avoid everything being filtered out
        raise "do not set a different PROJECT= when using TRACKING_ID="
      end
      (project_names || tracking_project_names)
    end

    def read_tracking_id_filter_from_env
      return unless (tracking_id = ENV["TRACKING_ID"])
      tracking_id.split(",").map do |id|
        # allow users to paste the generated/ path of an objects to update it without manually converting
        tracking_id_for_path(id)
      end.sort.uniq
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
