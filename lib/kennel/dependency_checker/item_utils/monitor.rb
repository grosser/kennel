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
          case object.fetch(:type)
          when "composite"
            object.fetch(:query).scan(/\d+/).map do |id|
              ResourceId.new(resource: "monitor", id: id.to_s)
            end
          end
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
