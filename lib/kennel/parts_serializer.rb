# frozen_string_literal: true

module Kennel
  class PartsSerializer
    def initialize(filter:)
      @filter = filter
    end

    def write(parts)
      Progress.progress "Storing" do
        existing = existing_files_and_folders
        used = write_changed(parts)
        FileUtils.rm_rf(existing - used)
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

    def existing_files_and_folders
      paths = Dir["generated/**/*"]

      if filter.filtering?
        segment = Kennel::Models::Record::ALLOWED_KENNEL_ID_SEGMENT
        paths.select! do |path|
          if (m = path.match(/^generated\/(#{segment})\/(#{segment})\.json$/o))
            filter.matches_tracking_id?("#{m[1]}:#{m[2]}")
          elsif (m = path.match(/^generated\/(#{segment})(?:\/|$)/o)) && File.directory?(path)
            filter.matches_project_id?(m[1])
          end
        end
      end

      paths
    end

    def path_for_tracking_id(tracking_id)
      "generated/#{tracking_id.tr("/", ":").sub(":", "/")}.json"
    end

    def write_file_if_necessary(path, content)
      # NOTE: always generating is faster than JSON.load-ing and comparing
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
