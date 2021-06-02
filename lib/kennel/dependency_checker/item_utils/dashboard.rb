# frozen_string_literal: true

require_relative './base'

module Kennel
  module DependencyChecker
    class ItemUtils

      class Dashboard < Base
        def kennel_id_text
          object.fetch(:description)
        end

        def dependencies
          object.fetch(:widgets).map do |widget|
            w = widget.fetch(:definition)
            case w.fetch(:type)
            when "slo"
              ResourceId.new(resource: "slo", id: w.fetch(:slo_id).to_s)
            end
          end.compact
        end

        def url
          "dashboard/#{id}"
        end

        def name
          object.fetch(:title)
        end

        def author
          object.fetch(:author_handle)
        end

        def tags
          nil # :-(
        end
      end

    end
  end
end
