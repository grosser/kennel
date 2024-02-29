# frozen_string_literal: true

module Kennel
  class Syncer
    class PlanPrinter
      def initialize
        @attribute_differ = AttributeDiffer.new
      end

      def print(plan)
        Kennel.out.puts "Plan:"
        if plan.empty?
          Kennel.out.puts Console.color(:green, "Nothing to do")
        else
          print_changes "Create", plan.creates, :green
          print_changes "Update", plan.updates, :yellow
          print_changes "Delete", plan.deletes, :red
        end
      end

      private

      def print_changes(step, list, color)
        return if list.empty?

        use_groups = ENV.key?("GITHUB_STEP_SUMMARY")

        list.each do |item|
          # No trailing newline
          Kennel.out.print "::group::" if item.class::TYPE == :update && use_groups

          Kennel.out.puts Console.color(color, "#{step} #{item.api_resource} #{item.tracking_id}")
          if item.class::TYPE == :update
            item.diff.each { |args| Kennel.out.puts @attribute_differ.format(*args) } # only for update
          end

          Kennel.out.puts "::endgroup::" if item.class::TYPE == :update && use_groups
        end
      end
    end
  end
end
