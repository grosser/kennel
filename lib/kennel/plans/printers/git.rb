# frozen_string_literal: true

require "open3"
require "shellwords"
require "tmpdir"

module Kennel
  module Plans
    module Printers
      class Git
        DIFF_COMMAND = "(cd %s && git --no-pager diff --no-prefix --color=always --no-index %s %s)"

        attr_reader :plan

        def initialize(plan, io)
          @plan = plan
          @io = io
        end

        def print!
          parent_directory, from_directory, to_directory = create_temporary_directories

          plan.diffs.each do |diff|
            from_string = serialize_contents(diff.from)
            to_string = serialize_contents(diff.to)

            unless diff.from.nil? || from_string.nil?
              pathname = File.join(from_directory, diff.from_identifier.to_s)
              File.write(pathname, from_string)
            end

            unless diff.to.nil? || to_string.nil?
              pathname = File.join(to_directory, diff.to_identifier.to_s)
              File.write(pathname, to_string)
            end
          end

          output = execute_diff!(parent_directory, from_directory, to_directory)
          io.puts(output)

          delete_temporary_directories(from_directory, to_directory)
        end

        private

        attr_reader :io

        def serialize_contents(contents)
          return nil if contents.nil?

          if contents.respond_to?(:as_json)
            contents = contents.as_json
          end

          contents = Utils.sorted_hash_enumeration_order(contents)

          JSON.pretty_generate(contents)
        end

        def execute_diff!(parent_directory, from_directory, to_directory)
          from_relative = from_directory.relative_path_from(parent_directory)
          to_relative = to_directory.relative_path_from(parent_directory)

          command = DIFF_COMMAND % [parent_directory, from_relative, to_relative]
          output, = Open3.capture2(command)
          output
        end

        def create_temporary_directories
          parent_directory = Pathname.new(Dir.mktmpdir)
          directories = ['a', 'b'].map(&parent_directory.method(:join))

          directories.each(&Dir.method(:mkdir))

          [parent_directory] + directories
        end

        def delete_temporary_directories(*directories)
          directories.each { |directory| FileUtils.remove_entry(directory) }
        rescue Errno::ENOENT
          # Ignored
        end
      end
    end
  end
end
