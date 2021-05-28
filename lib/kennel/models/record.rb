# frozen_string_literal: true
module Kennel
  module Models
    class Record < Base
      LOCK = "\u{1F512}"
      TRACKING_FIELDS = [:message, :description].freeze
      READONLY_ATTRIBUTES = [
        :deleted, :id, :created, :created_at, :creator, :org_id, :modified, :modified_at,
        :klass # added by syncer.rb
      ].freeze

      settings :id, :kennel_id

      class << self
        def parse_any_url(url)
          subclasses.detect do |s|
            if id = s.parse_url(url)
              break s.api_resource, id
            end
          end
        end

        def api_resource_map
          subclasses.map { |s| [s.api_resource, s] }.to_h
        end

        def parse_tracking_id(a)
          a[self::TRACKING_FIELD].to_s[/-- Managed by kennel (\S+:\S+)/, 1]
        end

        private

        def normalize(_expected, actual)
          self::READONLY_ATTRIBUTES.each { |k| actual.delete k }
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

        # strict: ignore Integer vs Float
        # similarity: show diff when not 100% similar
        # use_lcs: saner output
        Hashdiff.diff(actual, expected, use_lcs: false, strict: false, similarity: 1)
      end

      def tracking_id
        "#{project.kennel_id}:#{kennel_id}"
      end

      def resolve_linked_tracking_ids!(*)
      end

      def add_tracking_id
        json = as_json
        if self.class.parse_tracking_id(json)
          invalid! "remove \"-- Managed by kennel\" line it from #{self.class::TRACKING_FIELD} to copy a resource"
        end
        json[self.class::TRACKING_FIELD] =
          "#{json[self.class::TRACKING_FIELD]}\n" \
          "-- Managed by kennel #{tracking_id} in #{project.class.file_location}, do not modify manually".lstrip
      end

      def remove_tracking_id
        json = as_json
        value = json[self.class::TRACKING_FIELD]
        json[self.class::TRACKING_FIELD] =
          value.dup.sub!(/\n?-- Managed by kennel .*/, "") ||
          raise("did not find tracking id in #{value}")
      end

      private

      def resolve_link(tracking_id, type, id_map, force:)
        id = id_map[tracking_id]
        if id == :new
          if force
            invalid!(
              "#{type} #{tracking_id} was referenced but is also created by the current run.\n" \
              "It could not be created because of a circular dependency, try creating only some of the resources"
            )
          else
            nil # will be re-resolved after the linked object was created
          end
        elsif id
          id
        else
          invalid! "Unable to find #{type} #{tracking_id} (does not exist and is not being created by the current run)"
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
