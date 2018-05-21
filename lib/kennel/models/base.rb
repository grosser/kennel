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

        @invocation_location = caller.detect { |l| l.start_with?(Dir.pwd) }
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

        READONLY_ATTRIBUTES.each { |k| actual.delete k }

        diff = HashDiff.diff(actual, expected, use_lcs: false)
        diff if diff.any?
      end

      def tracking_id
        "#{project.kennel_id}:#{kennel_id}"
      end

      private

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
