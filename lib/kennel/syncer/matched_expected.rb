# frozen_string_literal: true

module Kennel
  class Syncer
    module MatchedExpected
      class << self
        def partition(expected, actual)
          lookup_map = matching_expected_lookup_map(expected)
          unmatched_expected = Set.new(expected) # for efficient deletion
          unmatched_actual = []
          matched = []
          actual.each do |a|
            e = matching_expected(a, lookup_map)
            if e && unmatched_expected.delete?(e)
              matched << [e, a]
            else
              unmatched_actual << a
            end
          end.compact
          [matched, unmatched_expected.to_a, unmatched_actual]
        end

        private

        # index list by all the thing we look up by: tracking id and actual id
        def matching_expected_lookup_map(expected)
          expected.each_with_object({}) do |e, all|
            keys = [e.tracking_id]
            keys << "#{e.class.api_resource}:#{e.id}" if e.id
            keys.compact.each do |key|
              raise "Lookup #{key} is duplicated" if all[key]
              all[key] = e
            end
          end
        end

        def matching_expected(a, map)
          klass = a.fetch(:klass)
          map["#{klass.api_resource}:#{a.fetch(:id)}"] || map[a.fetch(:tracking_id)]
        end
      end
    end
  end
end
