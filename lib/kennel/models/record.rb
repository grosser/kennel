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

      InvalidPart = Struct.new(:filtered_validation_errors, :tracking_id, :json, :unfiltered_validation_errors, keyword_init: true)

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
      ALLOWED_KENNEL_ID_FULL = "[#{ALLOWED_KENNEL_ID_CHARS}]+:[#{ALLOWED_KENNEL_ID_CHARS}]+"
      ALLOWED_KENNEL_ID_REGEX = /\A#{ALLOWED_KENNEL_ID_FULL}\z/.freeze

      settings :id, :kennel_id

      defaults(id: nil)

      class << self
        def built_class
          Built::Record
        end

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

        def normalize(_expected, actual)
          self::READONLY_ATTRIBUTES.each { |k| actual.delete k }
        end

        private

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

      attr_reader :project, :unfiltered_validation_errors

      def initialize(project, *args)
        raise ArgumentError, "First argument must be a project, not #{project.class}" unless project.is_a?(Project)
        @project = project
        super(*args)
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
            raise PrepareError, safe_tracking_id
          end
        end

        errors = filter_validation_errors

        if errors.empty?
          self.class.built_class.new(
            as_json: json,
            project: project,
            unbuilt_class: self.class,
            tracking_id: tracking_id,
            id: id,
            unfiltered_validation_errors: unfiltered_validation_errors
          )
        else
          InvalidPart.new(
            filtered_validation_errors: errors,
            tracking_id: tracking_id,
            json: json,
            unfiltered_validation_errors: unfiltered_validation_errors
          )
        end
      end

      def build!
        build.tap do |result|
          if result.is_a?(InvalidPart)
            raise "Invalid record: #{result.filtered_validation_errors.inspect}"
          end
        end
      end

      # For use during error handling
      def safe_tracking_id
        tracking_id
      rescue StandardError
        "<unknown; #tracking_id crashed>"
      end

      private

      def invalid!(tag, message)
        unfiltered_validation_errors << ValidationMessage.new(tag || OptionalValidations::UNIGNORABLE, message)
      end

      def raise_with_location(error, message)
        super error, "#{message} for project #{project.kennel_id}"
      end
    end
  end
end
