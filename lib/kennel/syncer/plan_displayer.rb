# frozen_string_literal: true

module Kennel
  class Syncer
    class PlanDisplayer
      def initialize
        @attribute_differ = AttributeDiffer.new
      end

      def display(internal_plan)
        Kennel.out.puts "Plan:"
        if internal_plan.empty?
          Kennel.out.puts Console.color(:green, "Nothing to do")
        else
          print_changes "Create", internal_plan.creates, :green
          print_changes "Update", internal_plan.updates, :yellow
          print_changes "Delete", internal_plan.deletes, :red
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
