# frozen_string_literal: true

module Kennel
  class Filter
    def initialize
      project_filter
      tracking_id_filter
    end

    def project_filter
      projects = ENV["PROJECT"]&.split(",")
      tracking_projects = tracking_id_filter&.map { |id| id.split(":", 2).first }
      if projects && tracking_projects && projects != tracking_projects
        raise "do not set PROJECT= when using TRACKING_ID="
      end
      projects || tracking_projects
    end

    def tracking_id_filter
      (tracking_id = ENV["TRACKING_ID"]) && tracking_id.split(",")
    end

    def self.filter_resources!(resources, by, against, name, env)
      return unless against

      against = against.uniq
      before = resources.dup
      resources.select! { |p| against.include?(p.send(by)) }
      keeping = resources.uniq(&by).size
      return if keeping == against.size

      raise <<~MSG.rstrip
        #{env}=#{against.join(",")} matched #{keeping} #{name}, try any of these:
        #{before.map(&by).sort.uniq.join("\n")}
      MSG
    end
  end
end
