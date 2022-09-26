# frozen_string_literal: true

module Kennel
  class PartsSerializer
    def initialize(filter:)
      @filter = filter
    end

    def write(parts)
      Progress.progress "Storing" do
        if filter.tracking_id_filter
          write_changed(parts)
        else
          old = old_paths
          used = write_changed(parts)
          (old - used).uniq.each { |p| FileUtils.rm_rf(p) }
        end
      end
    end

    private

    attr_reader :filter

    def write_changed(parts)
      used = []

      Utils.parallel(parts, max: 2) do |part|
        path = "generated/#{part.tracking_id.tr("/", ":").sub(":", "/")}.json"

        used << File.dirname(path) # only 1 level of sub folders, so this is enough
        used << path

        payload = part.as_json.merge(api_resource: part.class.api_resource)
        write_file_if_necessary(path, JSON.pretty_generate(payload) << "\n")
      end

      used
    end

    def directories_to_clean_up
      if filter.project_filter
        filter.project_filter.map { |project| "generated/#{project}" }
      else
        ["generated"]
      end
    end

    def old_paths
      Dir["{#{directories_to_clean_up.join(",")}}/**/*"]
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
