# frozen_string_literal: true
module Kennel
  module Models
    class Record < Base
      class PrepareError < StandardError
        def initialize(tracking_id)
          super("Error while preparing #{tracking_id}")
        end
      end

      UnvalidatedRecordError = Class.new(StandardError)

      include OptionalValidations

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
      ALLOWED_KENNEL_ID_SEGMENT = /[#{ALLOWED_KENNEL_ID_CHARS}]+/
      ALLOWED_KENNEL_ID_FULL = "#{ALLOWED_KENNEL_ID_SEGMENT}:#{ALLOWED_KENNEL_ID_SEGMENT}".freeze
      ALLOWED_KENNEL_ID_REGEX = /\A#{ALLOWED_KENNEL_ID_FULL}\z/

      settings :id, :kennel_id

      defaults(id: nil)

      class << self
        def parse_any_url(url)
          subclasses.detect do |s|
            if id = s.parse_url(url)
              break s.api_resource, id
            end
          end
        end

        def api_resource_map
          subclasses.to_h { |s| [s.api_resource, s] }
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

      attr_reader :project, :unfiltered_validation_errors, :filtered_validation_errors

      def initialize(project, *args)
        raise ArgumentError, "First argument must be a project, not #{project.class}" unless project.is_a?(Project)
        @project = project
        super(*args)
      end

      def diff(actual)
        expected = as_json
        expected.delete(:id)

        self.class.send(:normalize, expected, actual)

        return [] if actual == expected # Hashdiff is slow, this is fast

        # strict: ignore Integer vs Float
        # similarity: show diff when not 100% similar
        # use_lcs: saner output
        Hashdiff.diff(actual, expected, use_lcs: false, strict: false, similarity: 1)
      end

      def tracking_id
        @tracking_id ||= begin
          id = "#{project.kennel_id}:#{kennel_id}"
          unless id.match?(ALLOWED_KENNEL_ID_REGEX) # <-> parse_tracking_id
            raise "Bad kennel/tracking id: #{id.inspect} must match #{ALLOWED_KENNEL_ID_REGEX}"
          end
          id
        end
      end

      def resolve_linked_tracking_ids!(*)
      end

      def add_tracking_id
        json = as_json
        if self.class.parse_tracking_id(json)
          raise "#{safe_tracking_id} Remove \"-- #{MARKER_TEXT}\" line from #{self.class::TRACKING_FIELD} to copy a resource"
        end
        json[self.class::TRACKING_FIELD] =
          "#{json[self.class::TRACKING_FIELD]}\n" \
          "-- #{MARKER_TEXT} #{tracking_id} in #{project.class.file_location}, do not modify manually".lstrip
      end

      def remove_tracking_id
        self.class.remove_tracking_id(as_json)
      end

      def build_json
        {
          id: id
        }.compact
      end

      def build
        @unfiltered_validation_errors = []
        json = nil

        begin
          json = build_json
          (id = json.delete(:id)) && json[:id] = id
          validate_json(json)
        rescue StandardError
          if unfiltered_validation_errors.empty?
            @unfiltered_validation_errors = nil
            raise PrepareError, safe_tracking_id # FIXME: this makes errors hard to debug when running tests
          end
        end

        @filtered_validation_errors = filter_validation_errors
        @as_json = json # Only valid if filtered_validation_errors.empty?
      end

      def as_json
        # A courtesy to those tests that still expect as_json to perform validation and raise on error
        build if @unfiltered_validation_errors.nil?
        raise UnvalidatedRecordError, "#{safe_tracking_id} as_json called on invalid part" if filtered_validation_errors.any?

        @as_json
      end

      # Can raise DisallowedUpdateError
      def validate_update!(_diffs)
      end

      def invalid_update!(field, old_value, new_value)
        raise DisallowedUpdateError, "#{safe_tracking_id} Datadog does not allow update of #{field} (#{old_value.inspect} -> #{new_value.inspect})"
      end

      # For use during error handling
      def safe_tracking_id
        tracking_id
      rescue StandardError
        "<unknown; #tracking_id crashed>"
      end

      private

      def validate_json(data)
        bad = Kennel::Utils.all_keys(data).grep_v(Symbol).sort.uniq
        return if bad.empty?
        invalid!(
          :hash_keys_must_be_symbols,
          "Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
          "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
          "#{bad.map(&:inspect).join("\n")}"
        )
      end

      def resolve(value, type, id_map, force:)
        return value unless tracking_id?(value)
        resolve_link(value, type, id_map, force: force)
      end

      def tracking_id?(id)
        id.is_a?(String) && id.include?(":")
      end

      def resolve_link(sought_tracking_id, sought_type, id_map, force:)
        if id_map.new?(sought_type.to_s, sought_tracking_id)
          if force
            raise UnresolvableIdError, <<~MESSAGE
              #{tracking_id} #{sought_type} #{sought_tracking_id} was referenced but is also created by the current run.
              It could not be created because of a circular dependency. Try creating only some of the resources.
            MESSAGE
          else
            nil # will be re-resolved after the linked object was created
          end
        elsif id = id_map.get(sought_type.to_s, sought_tracking_id)
          id
        else
          raise UnresolvableIdError, <<~MESSAGE
            #{tracking_id} Unable to find #{sought_type} #{sought_tracking_id}
            This is either because it doesn't exist, and isn't being created by the current run;
            or it does exist, but is being deleted.
          MESSAGE
        end
      end

      def invalid!(tag, message)
        unfiltered_validation_errors << ValidationMessage.new(tag || OptionalValidations::UNIGNORABLE, message)
      end

      def raise_with_location(error, message)
        super error, "#{message} for project #{project.kennel_id}"
      end
    end
  end
end
