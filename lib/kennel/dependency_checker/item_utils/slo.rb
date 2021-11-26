# frozen_string_literal: true

require_relative './base'

module Kennel
  module DependencyChecker
    class ItemUtils

      class SLO < Base
        def kennel_id_text
          object.fetch(:description)
        end

        def dependencies
          found = Set.new

          case object.fetch(:type)
          when "monitor"
            object.fetch(:monitor_ids).each do |id|
              found << ResourceId.new(resource: "monitor", id: id.to_s)
            end
          end

          scan_text_for_dependencies(object[:description], "slo desc") { |dep| found.add(dep) }

          found
        end

        def url
          "slo?slo_id=#{id}"
        end

        def name
          object.fetch(:name)
        end

        def author
          object.fetch(:creator).fetch(:handle)
        end

        def tags
          object.fetch(:tags) + object.fetch(:monitor_tags)
        end
      end

    end
  end
end
