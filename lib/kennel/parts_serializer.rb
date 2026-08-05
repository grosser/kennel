# frozen_string_literal: true
require "etc"

Warning[:experimental] = false # silence "Ractor is experimental" noise

module Kennel
  class PartsSerializer
    FILE_EXTENSION = ".json"
    FOLDER = "generated"
    WORKERS = Etc.nprocessors

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
      used = []
      to_generate = []

      Utils.parallel(parts, max: 2) do |part|
        path = path_for_tracking_id(part.tracking_id)

        # match paths returned from existing_files_and_folders
        used << File.dirname(path) # we have 1 level of sub folders, so this is enough
        used << path

        content = part.as_json.merge(api_resource: part.class.api_resource)
        to_generate << [path, content]
      end

      changed = generate_and_write(to_generate)
      [used, changed]
    end

    # JSON.pretty_generate is CPU-bound, so Ractors (real parallelism, no GVL)
    # are used instead of threads (as used elsewhere in this file).
    # generate + write happen inside the Ractor so only a path (not the full
    # json content) needs to be copied back to the main Ractor.
    def generate_and_write(to_generate)
      return [] if to_generate.empty?

      workers = [WORKERS, to_generate.size].min
      chunks = to_generate.each_slice((to_generate.size.to_f / workers).ceil)

      ractors = chunks.map do |chunk|
        Ractor.new(chunk) do |items|
          items.each_with_object([]) do |(path, content), changed|
            # NOTE: always generating is faster than JSON.load-ing and comparing
            content = JSON.pretty_generate(content) << "\n"

            # 99% case
            begin
              next if File.read(path) == content
            rescue Errno::ENOENT # file or even folder did not exist
              FileUtils.mkdir_p(File.dirname(path))
            end

            # slow 1% case
            File.write(path, content)
            changed << path
          end
        end
      end

      ractors.flat_map(&:value)
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

    def suggest_using_project_filter(changed)
      return if filter.filtering?
      projects = changed.map { |path| path.split("/")[1] }.uniq
      return if projects.size != 1
      warn "Hint: Using PROJECT=#{projects[0]} is faster"
    end
  end
end
