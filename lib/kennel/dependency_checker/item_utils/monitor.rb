# frozen_string_literal: true

require_relative './base'

module Kennel
  module DependencyChecker
    class ItemUtils

      class Monitor < Base
        def kennel_id_text
          object.fetch(:message)
        end

        def dependencies
          found = Set.new

          case object.fetch(:type)
          when "composite"
            object.fetch(:query).scan(/\d+/).each  do |id|
              found << ResourceId.new(resource: "monitor", id: id.to_s)
            end
          end

          scan_text_for_dependencies(object[:message], "mon message") { |dep| found.add(dep) }
          scan_text_for_dependencies(object.dig(:options, :escalation_message), "mon esc") { |dep| found.add(dep) }

          found
        end

        def url
          "monitors/#{id}"
        end

        def name
          object.fetch(:name)
        end

        def author
          object.fetch(:creator).fetch(:handle)
        end

        def tags
          object.fetch(:tags)
        end
      end

    end
  end
end
