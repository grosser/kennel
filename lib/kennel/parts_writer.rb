# frozen_string_literal: true

require 'find'

module Kennel
  class PartsWriter
    def initialize(filter:)
      @filter = filter
    end

    def write(parts)
      Progress.progress "Storing" do
        old = old_paths
        used = ["generated"]

        Utils.parallel(parts, max: 2) do |part|
          path = "generated/#{part.tracking_id.tr("/", ":").sub(":", "/")}.json"
          used.concat [File.dirname(path), path] # only 1 level of sub folders, so this is safe
          payload = part.as_json.merge(api_resource: part.class.api_resource)
          write_file_if_necessary(path, JSON.pretty_generate(payload) << "\n")
        end

        # deleting all is slow, so only delete the extras
        (old - used).each { |p| FileUtils.rm_rf(p) }
      end
    end

    private

    attr_reader :filter

    def apply_cleanup_to
      if filter.tracking_id_filter
        [] # No cleanup
      elsif filter.project_filter
        filter.project_filter.map { |project| "generated/#{project}" }
      else
        ["generated"]
      end
    end

    def old_paths
      apply_cleanup_to.flat_map do |path|
        if File.exist?(path)
          Find.find(path).to_a
        else
          []
        end
      end
    end

    def write_file_if_necessary(path, content)
      # 99% case
      begin
        return if File.read(path) == content
      rescue Errno::ENOENT
        FileUtils.mkdir_p(File.dirname(path))
      end

      # slow 1% case
      File.write(path, content)
    end
  end
end
