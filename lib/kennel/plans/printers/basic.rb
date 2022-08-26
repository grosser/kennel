# frozen_string_literal: true

module Kennel
  module Plans
    module Printers
      class Basic
        attr_reader :plan

        def initialize(plan, io)
          @plan = plan
          @io = io
        end

        def print!
          print_plan @io, "Create", @plan.create, :green
          print_plan @io, "Update", @plan.update, :yellow
          print_plan @io, "Delete", @plan.delete, :red
        end

        private

        def print_plan(io, step, list, color)
          return if list.empty?
          list.each do |_, e, a, diff|
            klass = (e ? e.class : a.fetch(:klass))
            io.puts Utils.color(color, "#{step} #{klass.api_resource} #{e&.tracking_id || a.fetch(:tracking_id)}")
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
              Kennel.out.puts "  #{type}#{field}"
              Kennel.out.puts "    #{old} ->"
              Kennel.out.puts "    #{new}"
            else
              Kennel.out.puts "  #{type}#{field} #{old} -> #{new}"
            end
          end
        end
      end
    end
  end
end
