# frozen_string_literal: true
require "hashdiff"

module Kennel
  module Models
    class Base
      LOCK = "\u{1F512}"
      READONLY_ATTRIBUTES = [
        :deleted, :matching_downtimes, :id, :created, :created_at, :creator, :org_id, :modified,
        :overall_state_modified, :overall_state, :api_resource
      ].freeze
      REQUEST_DEFAULTS = {
        style: { width: "normal", palette: "dog_classic", type: "solid" },
        conditional_formats: [],
        aggregator: "avg"
      }.freeze
      OVERRIDABLE_METHODS = [:name, :kennel_id].freeze

      class ValidationError < RuntimeError
      end

      class << self
        include SubclassTracking

        def settings(*names)
          duplicates = (@set & names)
          if duplicates.any?
            raise ArgumentError, "Settings #{duplicates.map(&:inspect).join(", ")} are already defined"
          end

          overrides = ((instance_methods - OVERRIDABLE_METHODS) & names)
          if overrides.any?
            raise ArgumentError, "Settings #{overrides.map(&:inspect).join(", ")} are already used as methods"
          end

          @set.concat names
          names.each do |name|
            next if method_defined?(name)
            define_method name do
              message = "Trying to call #{name} for #{self.class} but it was never set or passed as option"
              raise_with_location ArgumentError, message
            end
          end
        end

        def defaults(options)
          options.each do |name, block|
            validate_setting_exists name
            define_method name, &block
          end
        end

        def inherited(child)
          super
          child.instance_variable_set(:@set, (@set || []).dup)
        end

        def validate_setting_exists(name)
          return if !@set || @set.include?(name)
          supported = @set.map(&:inspect)
          raise ArgumentError, "Unsupported setting #{name.inspect}, supported settings are #{supported.join(", ")}"
        end

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
            ignore_defaults e_r, a_r, REQUEST_DEFAULTS
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

      def initialize(options = {})
        validate_options(options)

        options.each do |name, block|
          self.class.validate_setting_exists name
          define_singleton_method name, &block
        end

        # need expand_path so it works wih rake and when run individually
        pwd = /^#{Regexp.escape(Dir.pwd)}\//
        @invocation_location = caller.detect do |l|
          if found = File.expand_path(l).sub!(pwd, "")
            break found
          end
        end
      end

      def kennel_id
        name = self.class.name
        if name.start_with?("Kennel::")
          raise_with_location ArgumentError, "Set :kennel_id"
        end
        @kennel_id ||= Utils.snake_case name
      end

      def name
        self.class.name
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

      def to_json
        raise NotImplementedError, "Use as_json"
      end

      def resolve_linked_tracking_ids(*)
      end

      private

      # let users know which project/resource failed when something happens during diffing where the backtrace is hidden
      def invalid!(message)
        raise ValidationError, "#{tracking_id} #{message}"
      end

      def raise_with_location(error, message)
        message = message.dup
        message << " for project #{project.kennel_id}" if defined?(project)
        message << " on #{@invocation_location}" if @invocation_location
        raise error, message
      end

      def validate_options(options)
        unless options.is_a?(Hash)
          raise ArgumentError, "Expected #{self.class.name}.new options to be a Hash, got a #{options.class}"
        end
        options.each do |k, v|
          next if v.class == Proc
          raise ArgumentError, "Expected #{self.class.name}.new option :#{k} to be Proc, for example `#{k}: -> { 12 }`"
        end
      end
    end
  end
end
