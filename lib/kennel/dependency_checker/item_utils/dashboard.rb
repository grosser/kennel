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
          require 'set'
          deps = Set.new
          each_dependency(object.fetch(:widgets)) { |dep| deps.add(dep) }
          deps
        end

        def each_dependency(widgets, &block)
          widgets.map do |widget|
            w = widget.fetch(:definition)
            t = w.fetch(:type)

            if t == "group"
              each_dependency(w[:widgets], &block)
              w[:widgets] = :dummy
            end

            if t == "note"
              w[:content] = :dummy # human text
            end

            if t == "slo"
              yield ResourceId.new(resource: "slo", id: w.fetch(:slo_id).to_s)
              w[:slo_id] = :dummy

              if w[:board_id]
                yield ResourceId.new(resource: "dashboard", id: w.fetch(:board_id).to_s)
                w[:board_id] = :dummy
              end
            end

            if t == "alert_graph" || t == "alert_value"
              yield ResourceId.new(resource: "monitor", id: w.fetch(:alert_id).to_s)
              w[:alert_id] = :dummy
            end

            if t == "timeseries"
              w[:markers]&.each do |marker|
                marker[:value] = :dummy # e.g. "y = 419430400"
                marker[:label] = :dummy # human text
              end

              w[:requests]&.each do |req|
                req[:q]&.gsub!(/\bcheck_id:\s*(\w\w\w-\w\w\w-\w\w\w)\b/) do |id|
                  yield ResourceId.new(resource: "synthetics/tests", id: id)
                  "dummy"
                end

                req[:queries]&.each do |query|
                  query[:query]&.gsub!(/\bcheck_id:\s*(\w\w\w-\w\w\w-\w\w\w)\b/) do |id|
                    yield ResourceId.new(resource: "synthetics/tests", id: id)
                    "dummy"
                  end
                end

                req[:metadata]&.each do |meta|
                  meta[:expression] = :dummy # a comment?
                end
              end

              w[:title] = :dummy # human text
            end

            w[:custom_links]&.each do |link|
              link[:link] = :dummy
              link[:label] = :dummy
            end

            # maybe_ids = []
            # w.inspect.scan(/\b(\d{6,9}|[0-9a-f]{32}|\w\w\w-\w\w\w-\w\w\w)\b/i) do |maybe_id, _|
            #   unless maybe_id.match(/^\d+00$/)
            #     maybe_ids << maybe_id
            #   end
            # end
            #
            # if maybe_ids.any?
            #   puts *maybe_ids
            #   puts JSON.pretty_generate({ widget: w })
            # end
          end
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
