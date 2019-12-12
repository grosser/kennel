# frozen_string_literal: true
module Kennel
  module Models
    class Record < Base
      LOCK = "\u{1F512}"
      READONLY_ATTRIBUTES = [
        :deleted, :id, :created, :created_at, :creator, :org_id, :modified, :modified_at, :api_resource
      ].freeze
      REQUEST_DEFAULTS = {
        style: { width: "normal", palette: "dog_classic", type: "solid" },
        conditional_formats: [],
        aggregator: "avg"
      }.freeze
      API_LIST_INCOMPLETE = false

      settings :id, :kennel_id

      class << self
        private

        def normalize(_expected, actual)
          self::READONLY_ATTRIBUTES.each { |k| actual.delete k }
        end

        # discard styles/conditional_formats/aggregator if nothing would change when we applied (both are default or nil)
        def ignore_request_defaults(expected, actual, level1, level2)
          actual = actual[level1] || {}
          expected = expected[level1] || {}
          [expected.size.to_i, actual.size.to_i].max.times do |i|
            a_r = actual.dig(i, level2, :requests) || []
            e_r = expected.dig(i, level2, :requests) || []
            ignore_defaults e_r, a_r, self::REQUEST_DEFAULTS
          end
        end

        def ignore_defaults(expected, actual, defaults)
          [expected&.size.to_i, actual&.size.to_i].max.times do |i|
            e = expected[i] || {}
            a = actual[i] || {}
            ignore_default(e, a, defaults)
          end
        end

        def ignore_default(expected, actual, defaults)
          definitions = [actual, expected]
          defaults.each do |key, default|
            if definitions.all? { |r| !r.key?(key) || r[key] == default }
              actual.delete(key)
              expected.delete(key)
            end
          end
        end
      end

      attr_reader :project

      def initialize(project, *args)
        raise ArgumentError, "First argument must be a project, not #{project.class}" unless project.is_a?(Project)
        @project = project
        super(*args)
      end

      def diff(actual)
        expected = as_json
        expected.delete(:id)

        self.class.send(:normalize, expected, actual)

        HashDiff.diff(actual, expected, use_lcs: false)
      end

      def tracking_id
        "#{project.kennel_id}:#{kennel_id}"
      end

      def resolve_linked_tracking_ids(*)
      end

      private

      def resolve_link(id, id_map, force:)
        id_map[id] || begin
          message = "Unable to find #{id} in existing monitors (they need to be created first to link them)"
          force ? invalid!(message) : Kennel.err.puts(message)
        end
      end

      # let users know which project/resource failed when something happens during diffing where the backtrace is hidden
      def invalid!(message)
        raise ValidationError, "#{tracking_id} #{message}"
      end

      def raise_with_location(error, message)
        super error, "#{message} for project #{project.kennel_id}"
      end
    end
  end
end
