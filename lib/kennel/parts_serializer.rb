# frozen_string_literal: true
require "etc"
require "parallel"

module Kennel
  class PartsSerializer
    FILE_EXTENSION = ".json"
    FOLDER = "generated"

    def initialize(filter:)
      @filter = filter
    end

    def write(parts)
      Progress.progress "Storing" do
        existing = existing_files_and_folders
        used, changed = write_changed(parts)
        FileUtils.rm_rf(existing - used) # cleanup abandoned
        suggest_using_project_filter(changed)
      end
    end

    class << self
      def tracking_id_for_path(path)
        path.sub("#{FOLDER}/", "").sub(FILE_EXTENSION, "").sub("/", ":")
      end
    end

    private

    attr_reader :filter

    def write_changed(parts)
      paths_used = []
      to_generate = []

      parts.each do |part|
        path = path_for_tracking_id(part.tracking_id)

        # match paths returned from existing_files_and_folders
        paths_used << File.dirname(path) # we have 1 level of sub folders, so this is enough
        paths_used << path

        content = part.as_json.merge(api_resource: part.class.api_resource)
        to_generate << [path, content]
      end

      paths_changed = generate_and_write(to_generate)

      [paths_used, paths_changed]
    end

    # JSON.pretty_generate is CPU-bound and threads are limited by the GVL, so we fork
    def generate_and_write(to_generate)
      chunks = to_generate.each_slice(100) # processing 1-by-1 would be slow

      Parallel.flat_map(chunks, exit!: true) do |chunk|
        chunk.filter_map { |path, content| path if write_file_if_necessary(path, content) }
      end
    end

    def existing_files_and_folders
      paths = Dir["#{FOLDER}/**/*"] # we rely on this returning folders and files, see write_changed

      # when filtering we only need the files we are going to write
      if filter.filtering?
        paths.select! do |path|
          tracking_id = self.class.tracking_id_for_path(path)
          filter.filters_tracking_id?(tracking_id)
        end
      end

      paths
    end

    def path_for_tracking_id(tracking_id)
      "#{FOLDER}/#{tracking_id.tr("/", ":").sub(":", "/")}#{FILE_EXTENSION}"
    end

    def write_file_if_necessary(path, content)
      # NOTE: always generating is faster than JSON.load-ing and comparing
      content = JSON.pretty_generate(content) << "\n"

      # 99% case
      begin
        return false if File.read(path) == content
      rescue Errno::ENOENT # file or even folder did not exist
        FileUtils.mkdir_p(File.dirname(path))
      end

      # slow 1% case
      File.write(path, content)
      true
    end

    def suggest_using_project_filter(changed)
      return if filter.filtering?
      projects = changed.map { |path| path.split("/")[1] }.uniq
      return if projects.size != 1
      warn "Hint: Using PROJECT=#{projects[0]} is faster"
    end
  end
end
