# frozen_string_literal: true

module Kennel
  class PartsSerializer
    def initialize(filter:)
      @filter = filter
    end

    def write(parts)
      Progress.progress "Storing" do
        existing = existing_paths
        used = write_changed(parts)
        FileUtils.rm_rf((existing - used).uniq)
      end
    end

    private

    attr_reader :filter

    def write_changed(parts)
      used = []

      Utils.parallel(parts, max: 2) do |part|
        path = path_for_tracking_id(part.tracking_id)

        used << File.dirname(path) # we have 1 level of sub folders, so this is enough
        used << path

        content = part.as_json.merge(api_resource: part.class.api_resource)
        write_file_if_necessary(path, content)
      end

      used
    end

    def existing_paths
      if filter.tracking_id_filter
        filter.tracking_id_filter.map { |tracking_id| path_for_tracking_id(tracking_id) }
      elsif filter.project_filter
        filter.project_filter.flat_map { |project| Dir["generated/#{project}/*"] }
      else
        Dir["generated/**/*"]
      end
    end

    def path_for_tracking_id(tracking_id)
      "generated/#{tracking_id.tr("/", ":").sub(":", "/")}.json"
    end

    def write_file_if_necessary(path, content)
      # note: always generating is faster than JSON.load-ing and comparing
      content = JSON.pretty_generate(content) << "\n"

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
