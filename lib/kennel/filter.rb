# frozen_string_literal: true

module Kennel
  class Filter
    attr_reader :project_filter, :tracking_id_filter

    # for testing
    def self.from(project_filter, tracking_id_filter)
      allocate.tap do |f|
        f.instance_variable_set(:@project_filter, project_filter)
        f.instance_variable_set(:@tracking_id_filter, tracking_id_filter)
      end
    end

    def initialize
      # build early so we fail fast on invalid user input
      @tracking_id_filter = build_tracking_id_filter
      @project_filter = build_project_filter
    end

    def filtering?
      !@project_filter.nil?
    end

    def filter_projects(projects)
      filter_resources(projects, :kennel_id, project_filter, "projects", "PROJECT", PartsSerializer.existing_project_ids)
    end

    def filter_parts(parts)
      filter_resources(parts, :tracking_id, tracking_id_filter, "resources", "TRACKING_ID", PartsSerializer.existing_tracking_ids)
    end

    def project_id_in_scope?(project_id)
      (project_filter.nil? || project_filter.include?(project_id))
    end

    def tracking_id_in_scope?(tracking_id)
      return true if project_filter.nil? # Minor optimization

      project_id = tracking_id.split(":")[0]
      project_id_in_scope?(project_id) && (tracking_id_filter.nil? || tracking_id_filter.include?(tracking_id))
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

    def filter_resources(resources, by, expected, _name, _env, existing)
      return resources unless expected

      matched = []
      useless = []

      expected.uniq.each do |exp|
        m = resources.select { |p| p.public_send(by) == exp }
        if m.empty?
          unless existing.include?(exp)
            useless << exp
          end
        else
          matched.concat(m)
        end
      end

      if useless.any?
        Kennel.err.puts "Warning: the following filter terms didn't match anything: #{useless.sort.join(", ")}"
      end

      # Preserve order
      # Should be unimportant but the tests care
      matched_object_ids = matched.map(&:object_id)
      resources.select { |r| matched_object_ids.include?(r.object_id) }
    end
  end
end
