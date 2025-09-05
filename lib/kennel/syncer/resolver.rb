# frozen_string_literal: true

require_relative "../id_map"

module Kennel
  class Syncer
    class Resolver
      def initialize(expected:, filter:)
        @id_map = IdMap.new
        @filter = filter

        # mark everything as new
        expected.each do |e|
          id_map.set(e.class.api_resource, e.tracking_id, IdMap::NEW)
          if e.class.api_resource == "synthetics/tests"
            id_map.set(Kennel::Models::Monitor.api_resource, e.tracking_id, IdMap::NEW)
          end
        end
      end

      def add_actual(actual)
        # override resources that exist with their id
        actual.each do |a|
          # ignore when not managed by kennel
          next unless (tracking_id = a.fetch(:tracking_id))

          # ignore when deleted from the codebase
          # (when running with filters we cannot see the other resources in the codebase)
          api_resource = a.fetch(:klass).api_resource
          next if !id_map.get(api_resource, tracking_id) && filter.matches_tracking_id?(tracking_id)

          id_map.set(api_resource, tracking_id, a.fetch(:id))
          if a.fetch(:klass).api_resource == "synthetics/tests"
            id_map.set(Kennel::Models::Monitor.api_resource, tracking_id, a.fetch(:monitor_id))
          end
        end
      end

      def resolve_as_much_as_possible(expected)
        expected.each do |e|
          e.resolve_linked_tracking_ids!(id_map, force: false)
        end
      end

      # loop over items until everything is resolved or crash when we get stuck
      # this solves cases like composite monitors depending on each other or monitor->monitor slo->slo monitor chains
      def each_resolved(list)
        list = list.dup
        loop do
          return if list.empty?
          size = list.size
          resolved = 0
          list.reject! do |item|
            if resolved?(item.expected)
              last_item = (resolved + 1 == size)
              yield item, last_item
              resolved += 1
              true
            else
              false
            end
          end ||
            assert_resolved(list[0].expected) # resolve something or show a circular dependency error
        end
      end

      private

      attr_reader :id_map, :filter

      # TODO: optimize by storing an instance variable if already resolved
      def resolved?(e)
        assert_resolved e
        true
      rescue UnresolvableIdError
        false
      end

      # raises UnresolvableIdError when not resolved
      def assert_resolved(e)
        e.resolve_linked_tracking_ids!(id_map, force: true)
      end
    end
  end
end
