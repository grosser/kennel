# frozen_string_literal: true
module Kennel
  module SettingsAsMethods
    SETTING_OVERRIDABLE_METHODS = [].freeze

    AS_PROCS = ->(options) do
      # Fragile; depends on the fact that in both locations where AS_PROCS is
      # used, we're 2 frames away from the user code.
      file, line, = caller(2..2).first.split(":", 3)

      options.transform_values do |v|
        if v.instance_of?(Proc)
          v
        else
          eval "-> { v }", nil, file, line.to_i
        end
      end
    end

    def self.included(base)
      base.extend ClassMethods
      base.instance_variable_set(:@settings, [])
    end

    module ClassMethods
      def settings(*names)
        duplicates = (@settings & names)
        if duplicates.any?
          raise ArgumentError, "Settings #{duplicates.map(&:inspect).join(", ")} are already defined"
        end

        overrides = ((instance_methods - self::SETTING_OVERRIDABLE_METHODS) & names)
        if overrides.any?
          raise ArgumentError, "Settings #{overrides.map(&:inspect).join(", ")} are already used as methods"
        end

        @settings.concat names

        names.each do |name|
          next if method_defined?(name)
          define_method name do
            raise_with_location ArgumentError, "'#{name}' on #{self.class} was not set or passed as option"
          end
        end
      end

      def defaults(options)
        AS_PROCS.call(options).each do |name, block|
          validate_setting_exist name
          define_method name, &block
        end
      end

      private

      def validate_setting_exist(name)
        return if @settings.include?(name)
        supported = @settings.map(&:inspect)
        raise ArgumentError, "Unsupported setting #{name.inspect}, supported settings are #{supported.join(", ")}"
      end

      def inherited(child)
        super
        child.instance_variable_set(:@settings, (@settings || []).dup)
      end
    end

    def initialize(options = {})
      super()

      unless options.is_a?(Hash)
        raise ArgumentError, "Expected #{self.class.name}.new options to be a Hash, got a #{options.class}"
      end

      AS_PROCS.call(options).each do |name, block|
        self.class.send :validate_setting_exist, name
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

    def raise_with_location(error, message)
      message = message.dup
      message << " on #{@invocation_location}" if @invocation_location
      raise error, message
    end
  end
end
