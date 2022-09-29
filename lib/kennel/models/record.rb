# frozen_string_literal: true
module Kennel
  module Models
    class Record < Base
      class IdLink
        def initialize(klass, id)
          @klass = klass
          @id = id.to_s
        end

        attr_reader :klass, :id
      end

      # Apart from if you just don't like the default for some reason,
      # overriding MARKER_TEXT allows for namespacing within the same
      # Datadog account. If you run one Kennel setup with marker text
      # A and another with marker text B (assuming that A isn't a
      # substring of B and vice versa), then the two Kennel setups will
      # operate independently of each other, not trampling over each
      # other's objects.
      #
      # This could be useful for allowing multiple products / projects
      # / teams to share a Datadog account but otherwise largely
      # operate independently of each other. In particular, it can be
      # useful for running a "dev" or "staging" instance of Kennel
      # in the same account as, but mostly isolated from, a "production"
      # instance.
      MARKER_TEXT = ENV.fetch("KENNEL_MARKER_TEXT", "Managed by kennel")

      LOCK = "\u{1F512}"
      TRACKING_FIELDS = [:message, :description].freeze
      READONLY_ATTRIBUTES = [
        :deleted, :id, :created, :created_at, :creator, :org_id, :modified, :modified_at,
        :klass, :tracking_id # added by syncer.rb
      ].freeze
      ALLOWED_KENNEL_ID_CHARS = "a-zA-Z_\\d.-"
      ALLOWED_KENNEL_ID_FULL = "[#{ALLOWED_KENNEL_ID_CHARS}]+:[#{ALLOWED_KENNEL_ID_CHARS}]+"
      ALLOWED_KENNEL_ID_REGEX = /\A#{ALLOWED_KENNEL_ID_FULL}\z/.freeze

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
          a[self::TRACKING_FIELD].to_s[/-- #{Regexp.escape(MARKER_TEXT)} (#{ALLOWED_KENNEL_ID_FULL})/, 1]
        end

        # TODO: combine with parse into a single method or a single regex
        def remove_tracking_id(a)
          value = a[self::TRACKING_FIELD]
          a[self::TRACKING_FIELD] =
            value.dup.sub!(/\n?-- #{Regexp.escape(MARKER_TEXT)} .*/, "") ||
            raise("did not find tracking id in #{value}")
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
        @tracking_id ||= begin
          id = "#{project.kennel_id}:#{kennel_id}"
          unless id.match?(ALLOWED_KENNEL_ID_REGEX) # <-> parse_tracking_id
            raise ValidationError, "#{id} must match #{ALLOWED_KENNEL_ID_REGEX}"
          end
          id
        end
      end

      def resolve_linked_tracking_ids!(*)
      end

      def find_links
      end

      def add_tracking_id
        json = as_json
        if self.class.parse_tracking_id(json)
          invalid! "remove \"-- #{MARKER_TEXT}\" line it from #{self.class::TRACKING_FIELD} to copy a resource"
        end
        json[self.class::TRACKING_FIELD] =
          "#{json[self.class::TRACKING_FIELD]}\n" \
          "-- #{MARKER_TEXT} #{tracking_id} in #{project.class.file_location}, do not modify manually".lstrip
      end

      def remove_tracking_id
        self.class.remove_tracking_id(as_json)
      end

      def validate_update!(*)
      end

      private

      def resolve(value, type, id_map, force:)
        return value unless tracking_id?(value)
        resolve_link(value, type, id_map, force: force)
      end

      def tracking_id?(id)
        id.is_a?(String) && id.include?(":")
      end

      def resolve_link(tracking_id, type, id_map, force:)
        if id_map.new?(type.to_s, tracking_id)
          if force
            invalid!(
              "#{type} #{tracking_id} was referenced but is also created by the current run.\n" \
              "It could not be created because of a circular dependency, try creating only some of the resources"
            )
          else
            nil # will be re-resolved after the linked object was created
          end
        elsif id = id_map.get(type.to_s, tracking_id)
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
