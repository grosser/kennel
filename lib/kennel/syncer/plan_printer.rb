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
        list.each do |item|
          Kennel.out.puts Console.color(color, "#{step} #{item.api_resource} #{item.tracking_id}")
          if item.class::TYPE == :update
            item.diff.each { |args| Kennel.out.puts @attribute_differ.format(*args) } # only for update
          end
        end
      end
    end
  end
end
