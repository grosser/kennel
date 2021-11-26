# frozen_string_literal: true

require 'uri'

module Kennel
  module DependencyChecker
    class Reporter

      def initialize(base_url: nil)
        @base_url = (URI.parse(base_url) if base_url)
      end

      def report(dependencies)
        deps = dependencies.map do |dep|
          from, to = dep[:from], dep[:to]

          owner = from[:teams]&.any? ? from[:teams].join(" ") : from[:author]

          from_type = from[:kennel_id] ? :kennel : :loose
          to_type = if to[:exists]
                      to[:kennel_id] ? :kennel : :loose
                    else
                      :dead
                    end

          {
            code: "from_#{from_type}_to_#{to_type}",
            from: {
              key: from[:key],
              exists: from[:exists], # always true
              url: resolve_url(from[:url]),
              name: from[:name],
              owner: owner,
              kennel_id: from[:kennel_id],
              # rest: dep[:from],
            },
            to: {
              key: to[:key],
              exists: to[:exists],
              kennel_id: to[:kennel_id],
              # rest: dep[:to],
            },
          }
        end

        deps.sort_by do |item|
          [
            item[:from][:key].resource, item[:from][:key].id,
            item[:to][:key].resource, item[:to][:key].id,
          ]
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
