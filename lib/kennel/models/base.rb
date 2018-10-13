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

      class ValidationError < RuntimeError
      end

      class << self
        include SubclassTracking

        def settings(*names)
          duplicates = (@set & names)
          if duplicates.any?
            raise ArgumentError, "Settings #{duplicates.map(&:inspect).join(", ")} are already defined"
          end

          @set.concat names
          names.each do |name|
            next if method_defined?(name)
            define_method name do
              raise ArgumentError, "Trying to call #{name} for #{self.class} but it was never set or passed as option"
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
      end

      def initialize(options = {})
        validate_options(options)

        options.each do |name, block|
          self.class.validate_setting_exists name
          define_singleton_method name, &block
        end

        # need expand_path so it works wih rake and when run individually
        @invocation_location = caller.detect { |l| File.expand_path(l).start_with?(Dir.pwd) }
      end

      def kennel_id
        name = self.class.name
        if name.start_with?("Kennel::")
          message = +"Set :kennel_id"
          message << " for project #{project.kennel_id}" if defined?(project)
          message << " on #{@invocation_location}" if @invocation_location
          raise ArgumentError, message
        end
        @kennel_id ||= Utils.snake_case name
      end

      def name
        self.class.name
      end

      def diff(actual)
        expected = as_json
        expected.delete(:id)

        self.class::READONLY_ATTRIBUTES.each { |k| actual.delete k }

        HashDiff.diff(actual, expected, use_lcs: false)
      end

      def tracking_id
        "#{project.kennel_id}:#{kennel_id}"
      end

      def to_json
        raise NotImplementedError, "Use as_json"
      end

      private

      # discard styles/conditional_formats/aggregator if nothing would change when we applied (both are default or nil)
      def ignore_request_defaults(expected, actual, level1, level2)
        expected[level1].each_with_index do |e_w, wi|
          e_r = e_w.dig(level2, :requests) || []
          a_r = actual.dig(level1, wi, level2, :requests) || []
          ignore_defaults e_r, a_r, REQUEST_DEFAULTS
        end
      end

      def ignore_defaults(expected, actual, defaults)
        expected.each_with_index do |e, i|
          next unless a = actual[i] # skip newly added
          defaults.each do |key, default|
            if [a, e].all? { |r| r[key].nil? || r[key] == default }
              a.delete(key)
              e.delete(key)
            end
          end
        end
      end

      # let users know which project/resource failed when something happens during diffing where the backtrace is hidden
      def invalid!(message)
        raise ValidationError, "#{tracking_id} #{message}"
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
