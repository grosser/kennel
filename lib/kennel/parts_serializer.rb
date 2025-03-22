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

      r = Array.new(10) do
        Ractor.new do
          loop do
            path, content = Ractor.receive

            # 99% case
            begin
              next if File.read(path) == content
            rescue Errno::ENOENT
              FileUtils.mkdir_p(File.dirname(path))
            end

            # slow 1% case
            File.write(path, content)
          end
        end
      end

      Utils.parallel(parts.each_with_index, max: 2) do |part, i|
        path = path_for_tracking_id(part.tracking_id)

        used << File.dirname(path) # we have 1 level of sub folders, so this is enough
        used << path

        content = part.as_json.merge(api_resource: part.class.api_resource)
        # write_file_if_necessary(path, content)
        c = JSON.pretty_generate(content) << "\n"
        r[i % 10].send([path, c])
      end

      parts.each_with_index do |_, i|
        r[i].take
      end

      used
    end

    def existing_files_and_folders
      paths = Dir["generated/**/*"]

      # when filtering we only need the files we are going to write
      if filter.filtering?
        paths.select! do |path|
          tracking_id = filter.tracking_id_for_path(path)
          filter.matches_tracking_id?(tracking_id)
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
