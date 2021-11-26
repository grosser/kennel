# frozen_string_literal: true

require_relative './base'

module Kennel
  module DependencyChecker
    class ItemUtils

      class SyntheticTest < Base
        def kennel_id_text
          object.fetch(:message)
        end

        def dependencies
          found = Set.new

          scan_text_for_dependencies(object[:message], "synth message") { |dep| found.add(dep) }

          found
        end

        def url
          "synthetics/details/#{id}"
        end

        def name
          object.fetch(:name)
        end

        def author
          nil
        end

        def tags
          object.fetch(:tags)
        end
      end

    end
  end
end
