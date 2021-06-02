# frozen_string_literal: true

require 'uri'

module Kennel
  module DependencyChecker
    class Reporter

      def initialize(base_url: nil)
        @base_url = (URI.parse(base_url) if base_url)
      end

      def report(dependencies)
        fragile = dependencies.map do |dep|
          from, to = dep[:from], dep[:to]

          owner = from[:teams]&.any? ? from[:teams].join(" ") : from[:author]

          if !to[:exists]
            # broken (maybe kennel maybe not)
            if from[:kennel_id]
              {
                code: :broken_kennel_object,
                url: resolve_url(from[:url]),
                name: from[:name],
                owner: owner,
                missing_dependency: to[:key],
                kennel_id: from[:kennel_id],
              }
            else
              {
                code: :broken_non_kennel_object,
                url: resolve_url(from[:url]),
                name: from[:name],
                owner: owner,
                missing_dependency: to[:key],
              }
            end
          elsif from[:kennel_id] && !to[:kennel_id]
            {
              code: :fragile_kennel_object,
              url: resolve_url(from[:url]),
              name: from[:name],
              owner: owner,
              non_kennel_dependency: to[:key],
              kennel_id: from[:kennel_id],
            }
          end
        end.compact

        fragile.sort_by do |item|
          [item[:url], item[:missing_dependency]&.id || item[:non_kennel_dependency].id]
        end
      end

      private

      def resolve_url(url)
        if @base_url
          (@base_url + url).to_s
        else
          url
        end
      end

    end
  end
end
