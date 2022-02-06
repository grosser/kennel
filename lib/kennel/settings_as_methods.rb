# frozen_string_literal: true
module Kennel
  module SettingsAsMethods
    SETTING_OVERRIDABLE_METHODS = [].freeze

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
        options.each do |name, block|
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

      options.each do |k, v|
        next if v.class == Proc
        raise ArgumentError, "Expected #{self.class.name}.new option :#{k} to be Proc, for example `#{k}: -> { 12 }`"
      end

      options.each do |name, block|
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
