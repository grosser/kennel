# frozen_string_literal: true

require "fileutils"
require "json"

require "kennel/progress"
require "kennel/utils"

module Kennel
  module PartsWriter
    class GeneratedDir
      def initialize(base_dir: "generated", project_filter: nil, tracking_id_filter: nil)
        @base_dir = base_dir
        @project_filter = project_filter
        @tracking_id_filter = tracking_id_filter
      end

      def store(parts:)
        Progress.progress "Storing" do
          ensure_dir_exists

          old = Dir[[
            # FIXME: characters like `{` and `}` in base_dir will break things
            base_dir,
            if project_filter || tracking_id_filter
              [
                "{" + (project_filter || ["*"]).join(",") + "}",
                "{" + (tracking_id_filter || ["*"]).join(",") + "}.json"
              ]
            else
              "**/*"
            end
          ].join("/")]
          used = []

          Utils.parallel(parts, max: 2) do |part|
            path = "#{base_dir}/#{part.tracking_id.tr("/", ":").sub(":", "/")}.json"
            used.concat [File.dirname(path), path] # only 1 level of sub folders, so this is safe
            payload = part.as_json.merge(api_resource: part.class.api_resource)
            write_file_if_necessary(path, JSON.pretty_generate(payload) << "\n")
          end

          # deleting all is slow, so only delete the extras
          (old - used).each { |p| FileUtils.rm_rf(p) }
        end
      end

      private

      attr_reader :base_dir, :project_filter, :tracking_id_filter

      def ensure_dir_exists
        Dir.mkdir(base_dir)
      rescue Errno::EEXIST
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
end
