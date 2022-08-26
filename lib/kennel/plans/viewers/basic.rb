# frozen_string_literal: true

module Kennel
  module Plans
    module Viewers
      class Basic
        class << self
          def available?
            true
          end
        end

        attr_reader :plan, :stdout, :stderr

        def initialize(plan:, stdout: STDOUT, stderr: STDERR)
          @plan = plan
          @stdout = stdout
          @stderr = stderr
        end

        def execute!
          print_plan "Create", @plan.create, :green
          print_plan "Update", @plan.update, :yellow
          print_plan "Delete", @plan.delete, :red
        end

        private

        def print_plan(step, list, color)
          return if list.empty?
          list.each do |_, e, a, diff|
            klass = (e ? e.class : a.fetch(:klass))
            stdout.puts Utils.color(color, "#{step} #{klass.api_resource} #{e&.tracking_id || a.fetch(:tracking_id)}")
            print_diff(diff) if diff # only for update
          end
        end

        def print_diff(diff)
          diff.each do |type, field, old, new|
            if type == "+"
              temp = Utils.pretty_inspect(new)
              new = Utils.pretty_inspect(old)
              old = temp
            else
              # ~ and -
              old = Utils.pretty_inspect(old)
              new = Utils.pretty_inspect(new)
            end

            if (old + new).size > 100
              stdout.puts "  #{type}#{field}"
              stdout.puts "    #{old} ->"
              stdout.puts "    #{new}"
            else
              stdout.puts "  #{type}#{field} #{old} -> #{new}"
            end
          end
        end
      end
    end
  end
end
