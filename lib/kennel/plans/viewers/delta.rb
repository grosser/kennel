# frozen_string_literal: true

require "open3"

module Kennel
  module Plans
    module Viewers
      class Delta
        DiffGenerationError = Class.new(StandardError)

        class << self
          def available?
            Utils.command_available?("delta")
          end
        end

        attr_reader :plan, :stdout, :stderr

        def initialize(plan:, stdout: STDOUT, stderr: STDERR)
          @plan = plan
          @stdout = stdout
          @stderr = stderr
        end

        def execute!
          with_transformed_stdout do |stdout|
            plan.diffs.each do |diff|
              description = create_description(diff)

              diff_objects = [diff.left, diff.right]
              diff_objects_serialized = diff_objects.map(&method(:serialize))

              output = invoke_diff(*diff_objects_serialized)

              if invoke_delta?
                output = invoke_delta(output)
              end

              stdout.puts(description)
              stdout.puts(output)
              stdout.puts
            end
          end
        end

        private

        def create_description(diff)
          if diff.create?
            api_resource = diff.right.value.class.api_resource
            id = diff.right.id

            color_string(:green, "Create #{api_resource} #{id}")
          elsif diff.update?
            api_resource = diff.left.value.class.api_resource
            id = diff.left.id

            color_string(:yellow, "Update #{api_resource} #{id}")
          elsif diff.delete?
            api_resource = diff.left.value.fetch(:klass).api_resource
            id = diff.left.id

            color_string(:red, "Delete #{api_resource} #{id}")
          end
        end

        def invoke_delta?
          stdout.isatty
        end

        def use_pager?
          stdout.isatty
        end

        def use_colored_output?
          stdout.isatty
        end

        def color_string(color, string)
          use_colored_output? ? Utils.color(color, string) : string
        end

        def with_transformed_stdout
          if use_pager?
            IO.popen(ENV.fetch("PAGER", "less"), "w") do |file|
              yield file
            end
          else
            yield stdout
          end
        end

        def invoke_delta(delta_stdin)
          stdout_str, status = \
            Open3.capture2(
              "delta",
              "--default-language=JSON",
              "--max-line-length=0",
              "--no-gitconfig",
              "--file-style=omit",
              "--hunk-header-style=omit",
              "--line-numbers",
              "--paging=never",
              stdin_data: delta_stdin
            )

          unless status.success?
            raise DiffGenerationError, "Could not print diff using command 'delta'."
          end

          stdout_str
        end

        def invoke_diff(left, right)
          diff_objects = [left, right]

          values = diff_objects.map do |diff_object|
            diff_object&.value
          end

          identifiers = diff_objects.map do |diff_object|
            diff_object&.id
          end

          identifier = identifiers.find { |id| !id.nil? }
          file_prefix = identifier ? identifier + "-" : ""

          files = values.map do |value|
            value ? Tempfile.new(file_prefix) : File.open(File::NULL, "w")
          end

          paths = files.map(&:path)

          begin
            values.zip(files).each do |(value, file)|
              file.write(value)
            end

            files.each(&:close)

            stdout_str, status = Open3.capture2("diff", "-u", *paths)

            if status == 2
              raise DiffGenerationError, "Could not generate diff using command 'diff'."
            end

            stdout_str
          ensure
            files.each do |file|
              file.unlink if file.is_a?(Tempfile)
            end
          end
        end

        def serialize(input)
          return nil if input.nil?

          output = input.dup

          if output.value.respond_to?(:as_json)
            output.value = output.value.as_json
          end

          output.value = Utils.sorted_hash_enumeration_order(output.value)
          output.value = JSON.pretty_generate(output.value)

          unless trailing_newline?(output.value)
            output.value = output.value + "\n"
          end

          output
        end

        def trailing_newline?(string)
          string.byteslice(-1) == "\n"
        end
      end
    end
  end
end
